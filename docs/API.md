# Warehouse Management REST API reference


| Method | Route | Success | Purpose |
|---|---|---|---|
| POST | /auth/register | 201 | Create account and issue token |
| POST | /auth/login | 200 | Verify credentials and issue token |
| GET | /auth/me | 200 | Read authenticated user |
| GET | /items | 200 | Search/filter/sort/page owned items |
| GET | /items/{id} | 200 | Read owned item |
| POST | /items | 201 | Create item; Location header points to new route |
| PUT | /items/{id} | 200 | Replace editable fields with version check |
| DELETE | /items/{id} | 204 | Delete owned item; no response body |

## Registration

```json
{"name":"Ahmad","email":"ahmad@example.com","password":"MyStrongPassword123!"}
```

Name is required and limited to 100 Java characters. Email is required, validated as an email address, and limited to 254 characters. Password needs 12–72 Java characters on registration and at most 72 UTF-8 bytes because BCrypt has a byte limit. Emails are trimmed and stored lowercase; names are trimmed. Duplicate normalized emails return 409.

## Login

```json
{"email":"ahmad@example.com","password":"MyStrongPassword123!"}
```

Login requires a nonblank password of at most 72 Java characters and 72 UTF-8 bytes. Incorrect credentials return 401; malformed or invalid request fields return 400.

Both authentication writes return:

```json
{
  "accessToken": "signed.jwt.value",
  "tokenType": "Bearer",
  "expiresIn": 3600,
  "user": {"id":"user-uuid","name":"Ahmad","email":"ahmad@example.com"}
}
```

## Create/update item

PUT sends all editable required fields; it is not a partial PATCH. Unknown JSON properties are rejected. Ownership comes only from the verified token.

```json
{
  "name":"Mechanical Keyboard",
  "sku":"KEY-001",
  "category":"Hardware",
  "quantity":10,
  "reorderLevel":3,
  "price":"149.90",
  "notes":"Black, USB-C"
}
```

For PUT, add `"version": 0` using the actual version returned by the last read. SKU allows letters, digits, underscores and hyphens; the service normalizes it uppercase. Price allows ten integer digits and two decimal places. Notes are optional, maximum 2000 characters.


| Field | Rules |
|---|---|
| name | Required, nonblank, maximum 120 characters; trimmed |
| sku | Required, 1–40 letters/digits/underscores/hyphens; normalized uppercase; unique per owner |
| category | Required, nonblank, maximum 80 characters; trimmed |
| quantity, reorderLevel | Required nonnegative 32-bit integers |
| price | Required nonnegative decimal, at most 10 integer digits and 2 fractional digits |
| notes | Optional, maximum 2000 characters; null becomes an empty string |
| version | Optional on create; required and nonnegative on update; must match the stored version |

An item is low stock when `quantity <= reorderLevel`. A stale update returns 409; fetch the latest item before retrying. DELETE does not accept a version precondition. A missing item and an item owned by another account both return 404.

## List

```text
/items?q=keyboard&category=Hardware&lowStock=true&page=0&size=10&sortBy=name&direction=asc
```

| Parameter | Default | Rules |
|---|---|---|
| q | empty | Case-insensitive substring; max 100 characters |
| category | empty | Exact category ignoring case; max 80 characters |
| lowStock | false | Boolean, quantity <= reorderLevel |
| page | 0 | Nonnegative |
| size | 10 | 1–100 |
| sortBy | updatedAt | name, sku, quantity, price, updatedAt |
| direction | desc | asc or desc |

```json
{"content":[],"totalElements":0,"totalPages":0,"page":0,"size":10}
```

## Errors

```json
{
  "timestamp":"2026-10-12T08:00:00Z",
  "status":400,
  "message":"Validation failed",
  "errors":{"quantity":"must be greater than or equal to 0"}
}
```

400 = invalid input; 401 = missing/invalid/expired token or wrong credentials; 403 = access denied; 404 = missing or unowned item; 409 = duplicate or stale update; 405 = unsupported method; 415 = unsupported request content type; 500 = unexpected failure.

CORS rejection occurs before the controller and may use Spring's filter response rather than this DTO.

## Mobile warehouse operations

All routes require a bearer token and derive ownership from its verified subject. Restart the updated backend to apply Flyway migration `V2__inventory_transactions.sql`.

| Method | Route | Success | Behavior |
|---|---|---|---|
| GET | `/operations/master` | 200 | Complete owned item master, ordered by SKU |
| POST | `/operations/transactions` | 200 | Apply one stock transaction or replay its receipt |
| GET | `/operations/transactions` | 200 | Latest 100 owned receipts, newest first |

Master response is `{"downloadedAt":"...","items":[ItemView,...]}` using the same item representation as `/items`. It is one database query, avoiding page drift. This endpoint is intended for modest item masters; it is not a paginated export or incremental sync protocol.

### Transaction upload

```json
{
  "clientId": "0692e2b3-5da6-4ee1-9bd5-bac15daa9f0a",
  "itemId": "e0194fd9-431a-45aa-85d4-b8503d61f45c",
  "type": "STOCK_COUNT",
  "quantity": 12,
  "expectedVersion": 3,
  "reference": "COUNT-2026-11-03-A",
  "notes": "Physical count at shift start"
}
```

- `clientId`: required UUID generated and saved by the device before sending; unique per owner.
- `itemId`: required owned item UUID. Missing or unowned items return 404.
- `type`: `STOCK_COUNT`, `GOODS_IN`, or `GOODS_OUT`.
- `quantity`: nonnegative 32-bit integer. Count means absolute quantity and permits zero. Goods in/out mean units added/subtracted and require at least one.
- `expectedVersion`: required for a count and must match the current item version; stale/missing count versions return 409. Goods in/out should send null and apply against current stock.
- `reference`: required nonblank document/count reference, at most 100 characters; trimmed.
- `notes`: required string (empty is valid), at most 2000 characters; trimmed.

Goods out that would make stock negative returns 409. Integer overflow returns 400. The server locks the owned item and commits its quantity plus an immutable movement receipt in one SQL transaction. Per-account upload locking serializes duplicate concurrent requests before checking the idempotency key. Ordinary item updates remain protected by the item's optimistic version.

Example receipt:

```json
{
  "id": "28d890ca-1ee3-497d-88db-fd6414473c2f",
  "clientId": "0692e2b3-5da6-4ee1-9bd5-bac15daa9f0a",
  "itemId": "e0194fd9-431a-45aa-85d4-b8503d61f45c",
  "sku": "BOX-001",
  "type": "STOCK_COUNT",
  "quantity": 12,
  "reference": "COUNT-2026-11-03-A",
  "notes": "Physical count at shift start",
  "beforeQuantity": 10,
  "afterQuantity": 12,
  "appliedVersion": 4,
  "uploadedAt": "2026-11-03T01:00:00Z"
}
```

Retrying the same owner/clientId with the same payload returns the original receipt without changing stock again, even after item deletion. A different payload with an already-used ID returns 409. Do not generate a new ID after a timeout; retry the original. Receipt timestamps use microsecond precision for stable first/replay responses. There is no receipt delete/update endpoint; the journal deliberately survives inventory item deletion.

The API applies individual lines, not an atomic multi-line document. Clients stop on an unresolved line to preserve queue order. Formal documents, stocktake approval, lot/bin tracking, and transfers remain outside this contract. See the [mobile operations guide](../flutter-app/docs/OPERATIONS.md).
