# SpendWise

**Private. Local. Yours.**

[![Flutter CI](https://github.com/abdullah270602/spendwise-local/actions/workflows/flutter.yml/badge.svg)](https://github.com/abdullah270602/spendwise-local/actions/workflows/flutter.yml)
[![Latest release](https://img.shields.io/github/v/release/abdullah270602/spendwise-local?display_name=tag)](https://github.com/abdullah270602/spendwise-local/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-60D394.svg)](LICENSE)

[**Download the latest Android APK**](https://github.com/abdullah270602/spendwise-local/releases/latest/download/spendwise-local.apk)

SpendWise is an Android-first, privacy-first personal finance ledger built with Flutter. It turns financial notification evidence, CSV/Excel statement rows, and manual entries into canonical local transactions.

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
- Everyday and savings accounts with separate available/saved totals
- Manual income/expense/transfer entry, ledger search, and filters
- Conservative CSV, XLSX, and XLS statement import with local CSV export
- Smart bank-table detection skips statement titles, account metadata, and blank rows before the real transaction header
- Editable column mappings, remembered statement formats, duplicate previews, and import batches
- Evidence timelines, source health, category analytics, filtered CSV/JSON export, and removable demo data
- One-action local data erasure

There is no backend, account system, telemetry, analytics, advertising, crash reporter, AI integration, or `INTERNET` permission.

## Install on Android

1. Download [`spendwise-local.apk`](https://github.com/abdullah270602/spendwise-local/releases/latest/download/spendwise-local.apk).
2. Open the downloaded file on Android 7.0 or newer.
3. If Android asks, allow your browser or file manager to install this one unknown app.
4. Install SpendWise, then revoke that installer permission if you no longer need it.

The GitHub APK is an early community build signed with the project's development key. Android may show an unfamiliar-app warning because it is distributed outside Google Play. Verify the SHA-256 checksum published in the matching [GitHub Release](https://github.com/abdullah270602/spendwise-local/releases/latest) before installing.

## Build from source

Requirements: Flutter 3.47+, Dart 3.13+, Android SDK 37, JDK 17 or newer.

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

The debug APK is written to `build/app/outputs/flutter-apk/app-debug.apk`.

## First run

1. Add the bank, wallet, cash, card, or savings accounts you want to track. Savings remain in **Accounts** and the combined **Insights** total, stay excluded from **Available to spend**, and can optionally be shown on Home.
2. Open Settings → Notification access and grant Android notification-listener access.
3. Enable only the financial source apps you want SpendWise to observe.
4. Use the ledger normally; uncertain evidence appears in Review.

Notification access is an Android Settings grant, not a normal runtime permission. SpendWise cannot grant it automatically.

## Privacy model

The ledger database, WAL, and journals are SQLCipher-encrypted. The native queue encrypts notification fields with AES-GCM under a non-exportable Android Keystore key before writing them. Android backup and device-transfer extraction are disabled. See [docs/PRIVACY.md](docs/PRIVACY.md).

SpendWise protects data at rest in the app sandbox; it cannot protect an already-unlocked, compromised device.

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

## Contributing and security

Contributions are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md), and use sanitized fixtures only—never commit real financial notifications, statements, account numbers, or secrets.

Please report vulnerabilities through a [private GitHub security advisory](https://github.com/abdullah270602/spendwise-local/security/advisories/new), not a public issue. See [SECURITY.md](SECURITY.md) for the threat model and reporting guidance.

## License

MIT
