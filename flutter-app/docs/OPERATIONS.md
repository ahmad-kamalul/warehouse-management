# Warehouse operations guide

## Start a shift

1. Start the updated Spring Boot backend. Flyway applies `V2__inventory_transactions.sql` automatically; V1 remains unchanged.
2. Run the updated Flutter app in API mode, then sign in to your account.
3. Tap the scanner icon in the inventory toolbar (**Warehouse operations**).
4. Tap **Download master**. The complete set of items owned by your account is saved on this device. Existing pending transactions remain intact.
5. Work through **Check stock**, **Stock count**, **Goods in**, **Goods out**, and **Transactions**.

In demo mode, the same screens operate against sample stock. Demo work resets at sign-out or restart. In API mode, downloaded master and transactions use app-private SQLite, partitioned by server URL and account ID. Logout removes data from the screen but retains that account's saved work for the next sign-in. Login after restart still requires a server connection; once signed in, lookup and recording can be used offline. Upload and master refresh always need the backend.

## Master download and stock check

**Download master** retrieves all owned items in one server query and replaces the local master only after the complete result is saved. It is a device data sync, not a CSV export. The time shown is the last full download time. Successful uploads update affected cached stock from their receipts without changing that full-download time.

Enter the exact SKU and press Enter/search, or tap the search icon. SKU matching ignores case and leading/trailing whitespace. Stock check shows the last known server quantity, quantity after pending local work, reorder level, and price. **Refresh stock from server** refreshes the full master. Other users/devices may change stock after a download; the displayed data is not a live availability guarantee.

## Scanning

- **Camera:** tap **Scan with camera** and allow camera access. Point at a barcode or QR code containing the item's exact SKU. A scan selects the item and closes the camera so you can review quantity. One camera visit accepts one value, avoiding duplicate camera frames being counted as units.
- **Hardware scanner:** use a keyboard-wedge scanner configured to send Enter after the barcode. Focus **Scan or enter SKU**; scanning the same SKU again increases the entry quantity by one. Text is selected after each accepted scan so the next code replaces it.
- **Manual entry:** enter the SKU and quantity directly. This also works when there is no camera or permission is denied.
- **Unknown code:** the app leaves current work intact and asks you to check the code or refresh the master. Supplier EAN/UPC-to-SKU mappings are not implemented; barcode content must match the stored SKU.

The scanner uses [mobile_scanner](https://pub.dev/packages/mobile_scanner), with Android camera permission and an iOS camera-purpose description. The default scanner widget owns its camera lifecycle. The bundled Android barcode engine supports scanning without an initial online model download.

## Stock take / stock count

Select **Stock count**, scan/select an item, and enter the **actual counted quantity**, including zero. Review the variance against last known stock. Enter a count reference such as `COUNT-2026-11-03-A`; reuse it for each item in the same physical count. Add optional notes, then **Save to transaction queue** and confirm.

This is an absolute quantity adjustment, not an increment. Each saved count retains the downloaded item version. Upload rejects the count if stock or the item changed since that version. Download fresh master data, cancel the rejected entry, physically recount, and save a new count. The app never silently changes a count's version to force acceptance. Upload or resolve prior pending work for an SKU before starting another count for that SKU.

Count lines are individual transactions grouped by your reference. Formal stocktake sessions with approval, locked bins, blind counts, and multi-counter reconciliation are not included.

## Goods in receiving

Select **Goods in**, scan/select the item, and enter units physically received. Repeated scans of the same SKU add one unit. Enter the supplier delivery note, GRN, or receipt reference and optional condition notes. Save and confirm each line.

The transaction adds units to the server quantity at upload time. It does not create a purchase order, supplier record, lot, serial number, or bin allocation.

## Goods out / dispatch

Select **Goods out**, scan/select the item, enter issued/dispatched units, and enter the delivery or issue reference. Save and confirm each line.

The local preview prevents obvious over-issues against downloaded stock plus pending work. The server validates against current stock during upload and rejects any result below zero. Goods out means issuing/dispatching goods; customer returns should be recorded as goods in with an explanatory reference.

## Upload inventory transactions

Open **Transactions**, review the queue, and tap **Upload inventory transactions**. Confirm before transmitting. Upload proceeds in saved order and stops at the first failure, preserving dependent later rows.

| Status | Meaning / next step |
|---|---|
| Queued | Saved on this device; has not been sent. Upload or cancel. |
| Awaiting confirmation | An upload was attempted but success is not confirmed. Retry the same entry. Cancellation is disabled. |
| Needs attention | Server explicitly rejected it (validation, missing item, stale count, or insufficient stock). Resolve the cause and retry, or cancel and record corrected work. |
| Uploaded | A server receipt is saved locally. Before/after quantity and receipt ID are shown. |
| Cancelled | Kept in local history, excluded from uploads and projected stock. |

Every entry has a UUID generated before saving. The server stores a receipt and the stock update in one SQL transaction. Retrying the same ID and payload returns the original receipt, including after a lost response or item deletion. Reusing the ID with different contents returns 409. A committed movement cannot be cancelled by deleting a queue row. Record an appropriate compensating movement if you need to reverse an uploaded movement.

The device saves an attempted marker before sending, and saves each confirmed receipt before proceeding. A local storage error prevents claiming success. If the network fails after a server commit, the entry remains recoverable using the original ID; **retry**, rather than recording the same physical movement as a new entry. Downloading master alone does not confirm a pending transaction's outcome.

## Storage and operating limits

- Saved work belongs to the device until uploaded. It does not automatically transfer with a Git pull or to another phone. Upload before changing devices or uninstalling the app.
- SQLite is app-private local storage, not an encrypted application database. No passwords or bearer tokens are written into it. Android application backup is disabled. iOS backup behavior follows the device's app-data policy; use managed-device controls if required.
- Local entries and receipts are retained; there is no automatic history pruning. Server history returns the latest 100 receipts per account; the full journal remains in SQL.
- Master download is an unpaged complete snapshot for modest account inventories. Large deployments should add versioned snapshot pagination and incremental master sync.
- Existing web/mobile item CRUD remains supported. Direct quantity edits through CRUD use optimistic version checks but do not create movement receipts. Use these operation screens for auditable operational stock changes.
- There is no background upload, automatic retry, full offline sign-in, unit conversion, location/warehouse selection, supplier/customer master, or document-line approval workflow.

## Verification

Automated tests cover 26 Flutter cases, including hardware-scanner Enter input, receiving and uploading through the UI, queue restoration, account separation, lost acknowledgements, stock-count conflicts, cancellation, write failures, and stale-receipt protection. Nine backend HTTP/SQL tests cover ownership, validation, atomic updates, audit history, idempotency, concurrent duplicate requests, overflow, and stale counts. Tests use H2 for the backend; PostgreSQL deployment and camera hardware need separate device acceptance testing. Android compilation is checked; iOS compilation requires a Mac.

Before rolling out: test camera permission denial, camera pause/resume, physical scanner Enter configuration, airplane mode and app restart, stock count conflicts from another device, and upload interruption against your deployed HTTPS API.

The [Android emulator acceptance suite](EMULATOR_TESTING.md) now verifies native camera preview and QR decoding, live API uploads, native SQLite persistence across force-stop/relaunch, real network disconnection/recovery, and count conflicts. Printed-barcode optics and physical scanner hardware still require device acceptance.
