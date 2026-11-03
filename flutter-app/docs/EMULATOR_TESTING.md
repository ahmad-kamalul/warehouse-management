# Android emulator acceptance tests

The device suite in `integration_test/warehouse_operations_test.dart` runs against the real API, camera plugin, and native SQLite implementation. The host runner in `tool/test-emulator.ps1` controls native camera permission, emulator connectivity, and a force-stop/relaunch checkpoint.

## Verified on 3 November 2026

All three native invocations passed on Android 16 / API 36 (x86_64), with Flutter 3.47.7 and Dart 3.13.5. The final workflow run took 86 seconds after installation, the process-restart run took 8 seconds, and native QR decoding took 1 second. Android build/install time is additional. The 26 unit/widget regression tests also passed, and static analysis found no issues.

| Device acceptance check | Result |
|---|---|
| UI sign-in against the real local API | Passed |
| Complete master download into native SQLite | Passed; two isolated test items |
| Exact stock lookup, Enter input, and unknown-SKU feedback | Passed |
| Native camera permission and preview texture | Passed |
| Stock count, goods in, goods out forms and ordered uploads | Passed; stock changed 10 → 8 → 13 → 10 |
| Count after another client's edit | Rejected as stale; stock retained at 11; rejected entry cancelled through UI |
| Physical count of zero | Passed; second item changed 2 → 0 |
| Replaying an old successful transaction | Passed; original receipt returned, no second stock change |
| Actual emulator network loss | Master refresh/upload failed; local master and newly queued goods in remained available |
| Reconnection and retry of the original UUID | Passed; goods in applied once, stock 11 → 12 |
| Sign-out/sign-in | Native master and pending queue restored |
| Force-stop and new app process | Exact pending UUID restored and uploaded once; stock 12 → 14 |
| Server journal after all retries | Exactly six receipts for six successful movements |
| Native Android ML Kit QR decoding | Fixture decoded as `EMU-BOX` |

The final run's saved restart UUID was `154239ba-be26-473d-9ecf-9c8e1454e2f5`. Detailed logs are in `.local-tools/emulator-checks/20261103-102642/` on the testing machine. A native [offline queue screenshot](screenshots/emulator-offline-queue.png) is included in source control; device timestamps in that image use the emulator's UTC timezone.

The device check prompted an input-focus correction: the SKU field now retains its Android input connection when Enter/search completes, rather than completing and immediately reopening it between scans.

## Rerun

Use a disposable local/test backend. The suite registers a unique test account, creates two owned inventory fixtures, and uploads real stock transactions for that account.

1. Start an Android emulator with both front and back cameras enabled. The test device used here is Android 16 / API 36, x86_64, 1080 × 2400. The emulator must advertise cameras consistent with its configuration; a disabled front camera can make CameraX reject camera enumeration.
2. Start the backend on port 8081 using the local profile and a generated JWT secret as described in the repository README. For example, append `--server.port=8081` to your Spring Boot launch arguments. Keep its test database separate from production data.
3. From `flutter-app/`, run:

```powershell
flutter pub get
.\tool\test-emulator.ps1 -Device emulator-5554 -ApiBaseUrl http://10.0.2.2:8081/api
```

If Flutter or adb is not on PATH, pass `-Flutter` and `-Adb` with their full executable paths. The runner uses a separate PowerShell job to monitor device checkpoints, always restores Wi-Fi/data in its `finally` block, and writes logs plus native screenshots under the repository's ignored `.local-tools/emulator-checks/<run>/` directory.

The runner performs three device invocations:

1. **workflows:** API fixture setup, UI sign-in, master sync, stock lookup, camera preview, count/receiving/dispatch forms, real uploads, conflict handling, offline failure/recovery, and sign-out/sign-in restore. It leaves one pending transaction in native SQLite.
2. **resume:** after an explicit `am force-stop`, launches a new app process, signs in, verifies the exact saved transaction UUID and master, and uploads that pending movement once.
3. **decoder:** writes a test-only QR fixture to app-private storage and asks Android ML Kit to decode `EMU-BOX`, then removes the temporary image. The fixture is bundled into the integration test source, not the production app's assets.

The runner passes `--no-uninstall`. Flutter otherwise removes the integration-test app and its database at the end of each invocation, which would test reinstall behavior rather than process-restart persistence. The helper explicitly force-stops the retained app between workflow and resume phases.

## Important test behavior

The suite waits for HTTP/SQLite operations to finish as well as for Flutter frames to settle. A loading indicator that has scrolled offscreen does not schedule frames, so frame settlement alone is insufficient for real device assertions.

Offline testing disables emulator Wi-Fi and cellular data and checks that the route to the host is unavailable before continuing. The suite proves that master refresh/upload fails while local lookup and recording remain available, then restores connectivity and retries the same saved UUID. Uploads are not mocked.

The SKU input keeps focus when Enter/search completes. This avoids closing/reopening the Android input connection between hardware scans. The native suite checks the count and receiving forms after leaving the camera screen.

## Scope

This suite verifies an emulator camera preview and Android's native QR decoder. It does not replace scanning printed barcodes with physical optics, testing a particular hardware scanner, iOS validation, PostgreSQL-specific deployment testing, or production-load testing. The backend fixture used for these emulator checks is file-backed H2 in PostgreSQL mode.
