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
