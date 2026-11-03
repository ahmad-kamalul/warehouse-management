# Developer notes

## Verification on 3 November 2026

Verified on Windows with Flutter 3.47.7 and Dart 3.13.5: 26 Flutter tests and nine backend HTTP/SQL integration tests passed. Static analysis, formatting, and the Android debug build are checked. Flutter transport tests use mocked HTTP; backend tests use H2. Physical camera/SQLite device acceptance, PostgreSQL operations verification, and a full mobile-to-deployed-backend run remain separate checks. The iOS host has not been compiled on this Windows machine. See the [operations guide](OPERATIONS.md) for workflow and recovery details.

## API mapping

All paths are relative to the configured URL ending in `/api`.

| User action | Request | Key behavior |
|---|---|---|
| Register | POST `/auth/register` | Name/email/password; stores returned token in memory |
| Sign in | POST `/auth/login` | Reads returned user and bearer token |
| Inventory | GET `/items` | q, category, lowStock, page, size=20, sortBy, direction |
| Reload conflict | GET `/items/{id}` | Replaces editor fields only after confirmation |
| Create | POST `/items` | All editable fields; decimal price string |
| Update | PUT `/items/{id}` | All editable fields plus observed version |
| Delete | DELETE `/items/{id}` | Accepts empty 204 response |
| Sign out | Local operation | Clears token and private inventory |
| Download master | GET `/operations/master` | Complete owned snapshot saved to SQLite |
| Upload movement | POST `/operations/transactions` | UUID idempotency; atomic stock plus receipt |
| Recent server journal | GET `/operations/transactions` | Latest 100 owned receipts |

See the [full API reference](../../docs/API.md) for server constraints and errors. Input names and shapes are intentionally shared with that contract; no alternative mobile API is invented.

## Checks

Run from `flutter-app/`:

```powershell
flutter pub get
dart format lib test
flutter analyze
flutter test
```

The tests exercise decimal and integer boundaries, UTF-8 password size, full update payload/version, token propagation, sign-out, field errors, 204 responses, connection errors, demo CRUD/conflicts, search races, session expiry, page shrinkage, low-stock filtering, create/search/delete UI, and unsaved-change confirmation. Test transport uses `http`'s `MockClient`; a fake repository controls response order. No production credentials or live database are needed.

A Windows golden screenshot checks a 390 × 844 phone layout with fonts from the installed Flutter SDK. To deliberately update that baseline after reviewing a design change:

```powershell
flutter test --update-goldens
```

Review the image under `docs/screenshots/` before accepting it. Other host platforms skip the golden comparison because font rasterization varies; functional UI assertions still run. These tests do not replace live backend or physical-device testing.

## Manual acceptance exercise

1. Start the backend and run the app in API mode. Register two separate accounts.
2. Create an item under account A, sign out, and verify account B cannot see it.
3. Add a SKU twice; verify the server's duplicate message appears.
4. Set quantity equal to reorder level; verify the low-stock filter includes it.
5. Update the same item in the web frontend, then save the old mobile editor. Verify 409 feedback and reload the latest item.
6. Stop the backend while viewing inventory. Refresh; verify the connection error and retry after restoring the backend.
7. Use an expired token; verify the app returns to sign-in and closes item routes.
8. Create enough rows for two pages and delete the last row on the last page.
9. Check keyboard, back gesture, landscape, large text, TalkBack/VoiceOver, and small-screen behavior on real devices.

## Android release signing

Debug APKs use the Android development key. Release builds use `android/key.properties` when supplied; there is no debug-key fallback for release. Copy `android/key.properties.example` to `android/key.properties`, replace its values, and supply your own upload keystore. Both the properties and keystores are ignored by Git. Store the key outside the repository and back it up securely.

```powershell
flutter build appbundle --release --dart-define=API_BASE_URL=https://your-warehouse.example/api
```

An unsigned release is not ready for store upload. Confirm the application ID is yours before publishing. Configure Play App Signing, signing secrets in your build environment, versioning, privacy disclosures, and a production HTTPS API. Android release manifest intentionally does not permit cleartext HTTP.

For iOS, open `ios/Runner.xcworkspace` on a Mac after Flutter setup, select your Apple team and bundle identifier, and run on a device. Configure distribution signing before `flutter build ipa`. The iOS host is generated but cannot be compiled or device-tested on Windows.

## Current boundaries

- Purchase orders, bin locations, transfers, multi-warehouse access, analytics exports, formal stocktake approval, and role management remain future work. Receiving, dispatch, stock counts, SKU scanning, and their upload journal are implemented.
- Login, master refresh, and uploads need the network. Downloaded master lookup and transaction recording work offline during a signed-in session; saved work is restored after the next online sign-in.
- JWTs are kept in memory; restart and expiry require sign-in. Password reset, email verification, refresh, revocation, and rate limiting remain backend work.
- DELETE has no version precondition in the current API; another client can update an item before you delete it. Confirmation does not provide concurrency protection.
- A CRUD write timeout has an unknown outcome; refresh before repeating a create. Operations uploads preserve their UUID and can be retried safely against the new idempotent endpoint.
- List totals reflect current search/filters. There are no global warehouse KPIs or inferred audit records.
- Category filter uses exact case-insensitive matching. Categories are entered as text because the API has no category directory endpoint.
- App icon/splash are Flutter's generated placeholders. Replace these, finalize release identifiers, and review accessibility/localization before store submission.
- Flutter tooling, Gradle, Android SDK, and dependency caches are machine-local and excluded from source control. Keep the supplied `pubspec.lock` in version control for reproducible app dependencies.
