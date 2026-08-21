# Contributing to SpendWise

Contributions are welcome, especially sanitized parser fixtures and deterministic parsing rules for Pakistani banks and wallets. Never commit real account numbers, card numbers, phone numbers, names, reference IDs, notification payloads, statements, API keys, or production database files.

Before submitting a change:

```powershell
dart format --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --debug
```

Keep domain logic deterministic and testable. Preserve raw evidence, explain every reconciliation decision, use integer minor units for money, and do not add network access, telemetry, analytics, tracking, or remote services. New Android capture fields must remain versioned and backward-compatible with queued snapshots.

Parser contributions should include sanitized positive, negative, malformed, and ambiguity fixtures. Rules must not merge transactions based on amount alone.
