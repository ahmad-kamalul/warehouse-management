param(
    [string]$Flutter = 'flutter',
    [string]$Adb = 'adb',
    [string]$Device = 'emulator-5554',
    [string]$ApiBaseUrl = 'http://10.0.2.2:8081/api'
)
$ErrorActionPreference = 'Stop'
$flutterExecutable = (Get-Command $Flutter -ErrorAction Stop).Source
$adbExecutable = (Get-Command $Adb -ErrorAction Stop).Source
$appDirectory = Split-Path -Parent $PSScriptRoot
$repository = Split-Path -Parent $appDirectory
$runName = Get-Date -Format 'yyyyMMdd-HHmmss'
$artifacts = Join-Path $repository ".local-tools/emulator-checks/$runName"
New-Item -ItemType Directory -Force $artifacts | Out-Null
$account = 'emulator.' + [Guid]::NewGuid().ToString('N') + '@example.test'
$account | Set-Content (Join-Path $artifacts 'account.txt')
$log = Join-Path $artifacts 'workflows.log'
$common = @('--no-version-check', 'test', 'integration_test/warehouse_operations_test.dart',
    '-d', $Device, '--no-pub', '--no-uninstall', "--dart-define=API_BASE_URL=$ApiBaseUrl", "--dart-define=E2E_ACCOUNT=$account")
$runArguments = $common + @('--dart-define=E2E_NETWORK_CONTROL=true')
$handled = @{ camera = $false; form = $false; offline = $false; online = $false }
$job = $null
try {
    # Flutter tests run in a hidden background PowerShell job so the host can
    # grant native permission and interrupt connectivity at explicit checkpoints.
    $job = Start-Job -ArgumentList $appDirectory, $flutterExecutable, $runArguments, $log -ScriptBlock {
        param($directory, $command, $arguments, $outputFile)
        Set-Location -LiteralPath $directory
        & $command @arguments *> $outputFile
        $LASTEXITCODE
    }
    $deadline = (Get-Date).AddMinutes(15)
    while ($job.State -eq 'Running') {
        if ((Get-Date) -gt $deadline) { throw 'Emulator workflow exceeded 15 minutes.' }
        [string]$output = if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Raw } else { '' }
        if ($output -match 'E2E_CAMERA_PERMISSION_READY' -and !$handled.camera) {
            $handled.camera = $true
            & $adbExecutable -s $Device shell pm grant com.ahmad.warehouse_mobile android.permission.CAMERA
            if ($LASTEXITCODE -ne 0) { throw 'Unable to grant emulator camera permission.' }
            & $adbExecutable -s $Device shell run-as com.ahmad.warehouse_mobile touch databases/e2e-camera-permission
            Write-Output 'Native camera permission granted for scanner check.'
        }
        if ($output -match 'E2E_FORM_READY' -and !$handled.form) {
            $handled.form = $true
            & $adbExecutable -s $Device shell screencap -p /sdcard/warehouse-entry.png
            & $adbExecutable -s $Device pull /sdcard/warehouse-entry.png (Join-Path $artifacts 'entry.png') | Out-Null
            & $adbExecutable -s $Device shell run-as com.ahmad.warehouse_mobile touch databases/e2e-form
        }
        if ($output -match 'E2E_OFFLINE_READY' -and !$handled.offline) {
            $handled.offline = $true
            & $adbExecutable -s $Device shell svc wifi disable
            & $adbExecutable -s $Device shell svc data disable
            $disconnected = $false
            for ($attempt = 0; $attempt -lt 20; $attempt++) {
                & $adbExecutable -s $Device shell ping -c 1 -W 1 10.0.2.2 *> $null
                if ($LASTEXITCODE -ne 0) { $disconnected = $true; break }
                Start-Sleep -Seconds 1
            }
            if (!$disconnected) { throw 'Emulator still has a network route; refusing to claim an offline test.' }
            & $adbExecutable -s $Device shell run-as com.ahmad.warehouse_mobile touch databases/e2e-offline
            Write-Output 'Emulator network disabled for offline recording and failed upload.'
        }
        if ($output -match 'E2E_ONLINE_READY' -and !$handled.online) {
            $handled.online = $true
            & $adbExecutable -s $Device shell screencap -p /sdcard/warehouse-offline.png
            & $adbExecutable -s $Device pull /sdcard/warehouse-offline.png (Join-Path $artifacts 'offline-queue.png') | Out-Null
            & $adbExecutable -s $Device shell svc wifi enable
            & $adbExecutable -s $Device shell svc data enable
            for ($attempt = 0; $attempt -lt 15; $attempt++) {
                & $adbExecutable -s $Device shell ping -c 1 -W 1 10.0.2.2 *> $null
                if ($LASTEXITCODE -eq 0) { break }
                Start-Sleep -Seconds 1
            }
            & $adbExecutable -s $Device shell run-as com.ahmad.warehouse_mobile touch databases/e2e-online
            Write-Output 'Emulator network restored; retrying the saved transaction.'
        }
        Start-Sleep -Milliseconds 300
    }
    $exitCode = Receive-Job $job
    Get-Content -LiteralPath $log -Tail 20
    if ($exitCode -ne 0) { throw "Workflow test failed. See $log" }
    $match = [regex]::Match((Get-Content -LiteralPath $log -Raw), 'E2E_RESTART_CLIENT_ID=([a-f0-9-]{36})')
    if (!$match.Success) { throw 'Workflow did not leave a restart checkpoint.' }
    $transactionId = $match.Groups[1].Value
    & $adbExecutable -s $Device shell am force-stop com.ahmad.warehouse_mobile
    Write-Output "App force-stopped. Verifying saved transaction $transactionId after a new launch."
    Push-Location -LiteralPath $appDirectory
    try {
        & $flutterExecutable @common '--dart-define=E2E_PHASE=resume' "--dart-define=E2E_EXPECT_ID=$transactionId" *> (Join-Path $artifacts 'restart.log')
        $resumeExit = $LASTEXITCODE
    } finally { Pop-Location }
    Get-Content (Join-Path $artifacts 'restart.log') -Tail 20
    if ($resumeExit -ne 0) { throw "Process-restart test failed. See $artifacts" }
    Push-Location -LiteralPath $appDirectory
    try {
        & $flutterExecutable @common '--dart-define=E2E_PHASE=decoder' *> (Join-Path $artifacts 'decoder.log')
        $decoderExit = $LASTEXITCODE
    } finally { Pop-Location }
    Get-Content (Join-Path $artifacts 'decoder.log') -Tail 12
    if ($decoderExit -ne 0) { throw "Native barcode decoder check failed. See $artifacts" }
    Write-Output "Emulator workflows, process restart and native barcode decoding passed. Evidence: $artifacts"
} finally {
    & $adbExecutable -s $Device shell svc wifi enable
    & $adbExecutable -s $Device shell svc data enable
    if ($null -ne $job) {
        if ($job.State -eq 'Running') { Stop-Job $job }
        Remove-Job $job
    }
}
