# Architecture and invariants

```text
Configured Android notification ─┐
CSV statement row ────────────────┼─> raw observation -> event candidate -> reconciliation -> transaction
Manual entry ─────────────────────┘
```

Raw observations are immutable evidence. They are never treated as ledger transactions directly. Parsing is deterministic and conservative: an amount needs an explicit currency marker and a direction needs an explicit sign or keyword. Unknown accounts and conflicting signals go to review.

Reconciliation runs on stable, sorted input. Same-account/same-direction observations can collapse only under explicit reference or cross-source/time/description rules. Equal debit and credit legs on distinct accounts within the transfer window form one internal transfer only when the match is unique. Manual and user-confirmed transactions are locked against automatic regrouping.

All monetary values are signed 64-bit minor units; database columns never use `REAL` for money.

## Notification durability

The Android listener filters against an explicit source allowlist and writes encrypted evidence before Flutter is notified. Flutter peeks a batch, commits idempotently using a stable native external ID, and acknowledges only successfully committed queue IDs. A process failure before acknowledgment causes safe replay.

## Trust boundaries

- Main ledger: SQLCipher key in secure storage/Android Keystore
- Native handoff queue: separate AES-GCM Android Keystore key
- UI/domain: no network API and no secret logging
- Export/import: Android Storage Access Framework; no broad storage permission
