# Warehouse Management TODO

Roadmap for a complete warehouse system. Checked items describe the implemented foundation; unchecked items remain planned.

## Priority 1 - Testing and setup

- [ ] Run tests automatically with GitHub Actions.
- [ ] Simplify setup with Maven Wrapper and Docker Compose.

## Priority 2 - Warehouse operations

- [x] Upload stock received/issued and absolute count adjustments, with immutable movement receipts and duplicate-safe retries.
- [ ] Manage multiple warehouses and storage locations.
- [ ] Transfer stock between locations.
- [x] Add receiving and dispatch movement records with document references.
- [x] Compare physical stock counts with downloaded quantities and validate versions on upload.
- [ ] Add formal receiving/dispatch documents and approved stocktake sessions.

## Priority 3 - Team access

- [ ] Add admin, operator, and read-only roles.
- [x] Keep an account-owned journal of uploaded inventory transactions.
- [ ] Audit direct CRUD quantity edits and add team actor attribution.
- [ ] Add password reset and login attempt limits.
- [ ] Improve session renewal and sign-out controls.

## Priority 4 - Daily usability

- [ ] Manage suppliers and suggest items to reorder.
- [x] Find items by scanning exact SKU barcodes (camera, hardware scanner, or manual entry).
- [ ] Map supplier EAN/UPC barcodes to inventory SKUs.
- [ ] Import and export inventory using CSV files.
- [ ] Upload product images.
- [ ] Show low-stock and inventory-value summaries.
- [ ] Improve keyboard navigation and accessibility.

## Priority 5 - Deployment and maintenance

- [ ] Set up HTTPS and secure deployment settings.
- [ ] Monitor application errors and performance.
- [ ] Automate database backups and test recovery.
- [ ] Test performance with larger inventories.
