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

A second invariant governs what the dashboard reports:

> What came in, minus everything that left, is the change in the spendable balance.

Spending is not the only way money leaves an account. A loan made, a borrowing repaid and a transfer into savings all reduce it without being spending, and a figure that ignores any of them drifts from the balances by exactly the amount ignored. `homeFigures` in `lib/features/dashboard/home_savings.dart` is the single assembly of those numbers; earnings and spending still come from the controller, which is the authority on what counts as either.

Debts carry two orthogonal facts: `direction` (which way the money moved) and `held` (whether it was ever the user's). Their three combinations are `DebtKind.lent`, `borrowed` and `holding`. Held money is stored as a borrowing that was never the user's rather than as a third `direction` value, because widening that column's CHECK constraint requires rebuilding the `debts` table and `transactions.debt_id` cascades on delete. Held money is subtracted from available-to-spend, and both its legs are excluded from the dashboard flow.

The pure-Dart domain layer owns exact minor-unit money, parser definitions, match scoring, and reversible reconciliation decisions. The data layer persists accounts, independent multi-source mappings, immutable evidence, categories, debts, decisions, and canonical transactions in SQLCipher. UI code consumes canonical state and never promotes an Android callback directly into the ledger.

The Android listener applies the explicit package allowlist before capture. It extracts public `StatusBarNotification`, content, messaging, action, ranking, channel, grouping, and lifecycle fields into a versioned snapshot. The snapshot is AES-GCM encrypted under Android Keystore before entering a bounded durable queue. Flutter uses peek, idempotent ledger commit, then acknowledgement, so process death can cause a safe replay but not silent loss.
