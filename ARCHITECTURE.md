# SpendWise architecture

SpendWise is an Android-first, offline ledger. Its central invariant is:

> A raw event is evidence, not a financial transaction.

```text
Notifications / Manual entry     
                 |
                 v
             Raw events
                 |
                 v
        Deterministic parsing
                 |
                 v
         Financial evidence
                 |
                 v
           Reconciliation
                 |
                 v
      Canonical transactions
                 |
                 v
          Analytics and UI
```

The pure-Dart domain layer owns exact minor-unit money, parser definitions, match scoring, and reversible reconciliation decisions. The data layer persists accounts, independent multi-source mappings, immutable evidence, categories, debts, decisions, and canonical transactions in SQLCipher. UI code consumes canonical state and never promotes an Android callback directly into the ledger.

The Android listener applies the explicit package allowlist before capture. It extracts public `StatusBarNotification`, content, messaging, action, ranking, channel, grouping, and lifecycle fields into a versioned snapshot. The snapshot is AES-GCM encrypted under Android Keystore before entering a bounded durable queue. Flutter uses peek, idempotent ledger commit, then acknowledgement, so process death can cause a safe replay but not silent loss.
