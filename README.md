# SpendWise

SpendWise is an Android-first, privacy-first personal finance ledger built with Flutter. It turns financial notification evidence, CSV statement rows, and manual entries into canonical local transactions.

> Raw event ≠ financial transaction.

A bank-app debit, an SMS alert for the same debit, and a wallet credit can describe one transfer. SpendWise retains the observations as evidence, then uses deterministic, explainable rules to produce one ledger entry.

## V1 capabilities

- Encrypted, local-only SQLCipher ledger with its key protected by Android Keystore
- Android `NotificationListenerService` with a separate Keystore-encrypted durable queue
- Explicit notification-source allowlist; unconfigured apps are never captured
- At-least-once native-to-Flutter handoff (`peek` → ledger commit → `ack`)
- Strict PKR/Rs amount and direction parsing without floating-point money
- Duplicate evidence collapse and debit/credit transfer reconciliation
- Review inbox for ambiguous or unsupported observations
- Accounts, balances, manual income/expense/transfer entry, search and filters
- Conservative CSV statement import and local CSV export
- Editable CSV mappings, remembered statement formats, duplicate previews, and import batches
- Evidence timelines, source health, category analytics, filtered CSV/JSON export, and removable demo data
- One-action local data erasure

There is no backend, account system, telemetry, analytics, advertising, crash reporter, AI integration, or `INTERNET` permission.

## Build

Requirements: Flutter 3.47+, Dart 3.13+, Android SDK 37, JDK 17 or newer.

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

The debug APK is written to `build/app/outputs/flutter-apk/app-debug.apk`.

## First run

1. Add the bank/wallet accounts you want to track.
2. Open Settings → Notification access and grant Android notification-listener access.
3. Enable only the financial source apps you want SpendWise to observe.
4. Use the ledger normally; uncertain evidence appears in Review.

Notification access is an Android Settings grant, not a normal runtime permission. SpendWise cannot grant it automatically.

## Privacy model

The ledger database, WAL, and journals are SQLCipher-encrypted. The native queue encrypts notification fields with AES-GCM under a non-exportable Android Keystore key before writing them. Android backup and device-transfer extraction are disabled. See [docs/PRIVACY.md](docs/PRIVACY.md).

SpendWise protects data at rest in the app sandbox; it cannot protect an already-unlocked, compromised device.

## Screenshots

Screenshots are intentionally left as placeholders until release branding is finalized:

- Home dashboard — `docs/screenshots/home.png`
- Transaction evidence — `docs/screenshots/evidence.png`
- CSV mapping wizard — `docs/screenshots/csv-import.png`

## Current limitations

- Android only; iOS, web, and desktop are out of scope for V1.
- Parsers are conservative and currently focus on explicit PKR/Rs Pakistani finance formats. Unsupported or ambiguous events remain reviewable evidence.
- Notification availability varies by the source app and Android version.
- Exports are plaintext after a clear warning; there is no automatic backup or sync.
- Optional BYOK AI is not shipped in V1. The deterministic ledger has no AI or network dependency.

## Architecture

- `lib/domain`: pure Dart money, evidence, parsing, and reconciliation
- `lib/data`: SQLCipher ledger and CSV ingestion
- `lib/platform`: Flutter/native notification bridge
- `lib/features`: Android-first Material UI
- `android/.../com/spendwise/app`: encrypted notification capture and queue

See [ARCHITECTURE.md](ARCHITECTURE.md) and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for invariants and data flow. The exact trust boundary is documented in [SECURITY.md](SECURITY.md).

## License

MIT
