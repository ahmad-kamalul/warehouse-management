# Mobile architecture

## Boundaries and flow

The project separates presentation from transport and persistence through a repository contract, following Flutter's architecture guidance: https://docs.flutter.dev/app-architecture/guide.

```text
Screen → WarehouseController → WarehouseRepository → ApiClient → Spring Boot
                                ↳ DemoWarehouseRepository
```

`main.dart` constructs dependencies once. The repository is injected into the controller and the controller into screens. No global mutable service locator is used. Flutter's `ChangeNotifier` and `ListenableBuilder` provide reactive state without another state-management dependency. The controller owns session and list state; short-lived form fields belong to their screen. The app owns and disposes its controller, which closes the HTTP client.

This is deliberately a small architecture. There is no empty use-case layer, generated DTO code, or one-class-per-field abstraction. Add another feature controller when a feature needs independent state instead of turning the warehouse controller into an application-wide object.

## Read flow

1. User changes search, stock filter, category, sort, or page.
2. The controller updates its immutable query and clears displayed results.
3. The repository serializes the query using the existing API contract.
4. A decoded page replaces the previous page; the API supplies totals.
5. A request generation counter discards results from older searches or a prior session.

Search is debounced for 350 ms. Explicit search submit cancels the debounce. Refresh, empty state, failure state, and pagination are available. Only the active page is fetched: the total shown is the backend's count of matching items. No global stock-value or low-stock count is inferred from a single page. After a mutation, list failures remain visible and retryable. Deleting the final row on the last page moves back to the last valid page.

## Write flow

The editor builds an immutable `ItemDraft`. The API adapter sends a full POST/PUT body. For updates it includes the **original server version**, never an invented increment. A stale update returns 409. The form preserves local input, shows the error, and offers an explicit reload that asks before discarding edits. Reload obtains the item by ID, so it works independently of the active list page. Duplicate-SKU conflicts may also return 409; the server message and any field errors remain visible.

The backend performs ownership checks and is the final validation authority. Client validation improves feedback only. The editor blocks duplicate submissions and back navigation during a write. Deletion is confirmed and irreversible. The existing API has no DELETE version precondition; see developer notes for the consequence.

## Session behavior

Bearer JWTs live only in `ApiClient` memory. Restarting the app requires signing in. There is no plaintext token persistence, refresh token, or credentials logging. A protected request returning 401 clears the token, user, query, inventory, and pending request generation. The app removes detail routes and returns to the sign-in screen with an expiry message.

The client does not decode JWTs to make authorization decisions. Expiry is detected on the next server request. Logout clears local state; the existing backend does not revoke an already copied token.

## Money and quantities

Prices use integer cents internally and a decimal string in writes. This avoids `double` accumulation for stock-value arithmetic. Currency remains MYR to match the existing backend. Quantities and reorder levels use nonnegative signed 32-bit integers. A low-stock item has `quantity <= reorderLevel`, including zero stock.

## Error handling

Transport failures and timeouts produce actionable messages. Requests time out after 20 seconds, including response bodies. `ApiException` preserves HTTP status and field messages. Empty 204 responses are accepted. Non-JSON responses are rejected as unreadable instead of crashing JSON decoding. Unknown exceptions use a generic UI message. There is no automatic write retry, because a timeout does not prove that a server write failed.

## Extending the app

- **Stock movements:** first add server-side atomic receive/dispatch endpoints with an audit trail and idempotency keys. Then add a movement repository operation, controller, and screen. Do not simulate an audit trail by changing quantity locally.
- **Barcode scan:** add camera permission and a scanner plugin, and use the scanned SKU as a search query. Keep manual entry available.
- **Offline support:** add durable local storage, per-account partitioning, an outbox, retry/idempotency policy, conflict resolution, and migration tests. The demo repository is not offline synchronization.
- **Locations and roles:** extend backend models and enforce authorization there before exposing UI controls.
- **Persistent sign-in:** use platform secure storage and a server-supported refresh/revocation design; never store passwords.

The mobile app shares the backend with the existing web frontend. It introduces no database migrations or backend changes.
