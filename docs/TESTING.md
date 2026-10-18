# Test this project

## Automated backend tests

From the project root in PowerShell:

```powershell
Set-Location backend
mvn verify
```

Run the entire test class or one method while working:

```powershell
mvn "-Dtest=ApiIntegrationTest" test
mvn "-Dtest=ApiIntegrationTest#crudEnforcesOwnershipAndDetectsStaleUpdates" test
```

### Run the suite against PostgreSQL

Create a separate, empty test database and set `DB_URL`, `DB_USER`, and `DB_PASSWORD` as shown in the README, pointing to that test database. From `backend/`, run:

```powershell
mvn -B "-Dspring.datasource.url=$env:DB_URL" "-Dspring.datasource.username=$env:DB_USER" "-Dspring.datasource.password=$env:DB_PASSWORD" verify
```


### Coverage map

| Test method in `ApiIntegrationTest` | What it checks |
|---|---|
| `registrationLoginAndProtectedRoutes` | Registration, no password hash in response, `/auth/me`, missing/invalid tokens, incorrect password, email case normalization, duplicate account |
| `crudEnforcesOwnershipAndDetectsStaleUpdates` | Create/update/delete, other-owner 404s, isolated list, version increment, stale update 409 |
| `validationUniquenessAndFiltersWork` | Negative quantity, normalized SKU uniqueness, low-stock/search/category filters, sort/pagination, invalid sort/page/size |
| `rejectsUnknownFieldsMalformedIdsAndMissingVersion` | Client `ownerId` rejection, required update version, malformed UUID, literal percent search |
| `corsAllowsOnlyConfiguredFrontend` | Allowed preflight origin and rejection of another origin |


### Register and create

```powershell
$apiBase = "http://localhost:8080/api"
$registration = @{
    name = "User"
    email = "learner-$([Guid]::NewGuid().ToString('N'))@example.com"
    password = "UserPassword123!"
}
$auth = Invoke-RestMethod -Method Post -Uri "$apiBase/auth/register" `
    -ContentType "application/json" -Body ($registration | ConvertTo-Json)
$headers = @{ Authorization = "Bearer $($auth.accessToken)" }
Invoke-RestMethod -Uri "$apiBase/auth/me" -Headers $headers

$itemBody = @{
    name = "User Keyboard"
    sku = "learn-01"
    category = "Hardware"
    quantity = 2
    reorderLevel = 5
    price = "99.90"
    notes = "Manual API exercise"
}
$created = Invoke-RestMethod -Method Post -Uri "$apiBase/items" -Headers $headers `
    -ContentType "application/json" -Body ($itemBody | ConvertTo-Json)
$created
```


### List, update, and reject a stale write

```powershell
Invoke-RestMethod -Uri "$apiBase/items?q=keyboard&category=Hardware&lowStock=true&page=0&size=10&sortBy=name&direction=asc" -Headers $headers

$itemBody.version = $created.version
$itemBody.quantity = 8
$updated = Invoke-RestMethod -Method Put -Uri "$apiBase/items/$($created.id)" `
    -Headers $headers -ContentType "application/json" -Body ($itemBody | ConvertTo-Json)
$updated

# Deliberately reuse the original version. Expect an HTTP 409 exception.
try {
    Invoke-RestMethod -Method Put -Uri "$apiBase/items/$($created.id)" `
        -Headers $headers -ContentType "application/json" -Body ($itemBody | ConvertTo-Json)
} catch {
    Write-Output "HTTP $([int]$_.Exception.Response.StatusCode)"
    Write-Output $_.ErrorDetails.Message
}
```

### Explore failures and ownership

| Action | Expected |
|---|---|
| List items without `Authorization` | 401 |
| Login with the registered email and wrong password | 401 |
| Register the same email again, including uppercase spelling | 409 |
| POST the original SKU again for this account | 409 |
| POST a new SKU with quantity `-1` | 400 |
| Add `ownerId` to item JSON | 400 |
| PUT a valid complete item body without `version` | 400 |
| GET `/items/not-a-uuid` with a valid token | 400 |
| List with `size=101`, `page=-1`, or `sortBy=ownerId` | 400 |
| Register a second account and list with its token | Empty inventory |
| GET, PUT, or DELETE the first account's item using the second token | 404 |
| Create the same SKU using the second account | 201 |

### Delete the exercise item

```powershell
Invoke-RestMethod -Method Delete -Uri "$apiBase/items/$($created.id)" -Headers $headers
```

## Manual browser checks

Start both servers and open `http://localhost:5173`. Use disposable accounts.


| Check | Expected result |
|---|---|
| Register, log out, and log in | Own account and inventory appear; bad credentials show an error |
| Add Keyboard, SKU `KEY-01`, quantity 2, reorder level 5 | Row appears and is marked low stock |
| Add Monitor, SKU `MON-01`, quantity 20, reorder level 5 | Row appears without low-stock marking |
| Search keyboard/SKU, filter category and low stock | Only matching rows appear; clearing filters restores rows |
| Sort and add enough rows to exceed the page size | Order and page controls reflect the data |
| Change Keyboard quantity to 8 | Updated row no longer shows low stock |
| Reuse `key-01` for another item | Duplicate error; original row remains |
| Delete an item, testing cancel first | Cancel preserves it; confirmation removes it |
| Log in as a second account | First account's rows are absent |
| Refresh the page | Sign-in is required because token storage is memory-only |
| Restart backend, then log in again | Remaining rows persist with local H2 or PostgreSQL |
| Resize to 320, 390, and 700 pixels wide | Equal page gutters; usable forms; labeled item cards show stock, badges, prices, and actions without horizontal page scrolling |
| Inspect Console and Network panels | No unexpected JavaScript errors; requests use the intended API URL |

## Troubleshooting

| Symptom | Check |
|---|---|
| `java` or `mvn` is not recognized | Install JDK 21/Maven, configure PATH and `JAVA_HOME`, then open a new terminal; check `mvn -version` |
| Missing or short `JWT_SECRET` | Generate it in the same terminal that starts the backend |
| PostgreSQL connection failure when you intended H2 | Include `"-Dspring-boot.run.profiles=local"` |
| Port 8080 or 5173 is occupied | Stop the existing server, or update port/API URL/origin settings consistently |
| Browser cannot connect or reports CORS | Check both servers, `frontend/config.js`, and exact `http://localhost:5173` origin |
| 401 after refresh, restart, or time passing | Sign in again; token may be absent, signed with an old secret, or expired |
| 409 on update | Read the latest item and resubmit your changes with its current version |
| Local data disappeared | Check whether `mvn clean` ran or the backend working directory changed |
| Java archive access error during compilation | Earlier local runs used `mvn "-Dmaven.compiler.fork=true" verify`; retry that command and inspect the actual error |
| Flyway checksum mismatch | Restore the applied migration and add a new numbered migration for changes |
