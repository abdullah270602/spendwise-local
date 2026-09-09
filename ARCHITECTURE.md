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

Two smaller contracts hold the UI together. A Review rule carries a list of `ReviewAction`s rather than one action plus an optional second, because its answers need different things — an account, a direction, nothing — and one set of flags on the rule meant the question that most needed a third answer could not have one. And a stored view preference notifies when it changes: writing to the ledger without announcing it left screens already built showing the previous choice, which made a setting look as though it did nothing.

Two contracts govern how categories are drawn. A category's colour comes from `CategoryTones`, keyed to the ledger's own category order rather than to its position in the list being drawn, because that position moves whenever spending does and a category that changes colour between two months cannot be recognised across them. And `SpendingAnalytics` exposes two lists rather than one: `categories` is this period's spending and answers "where your money went", while `categoryChanges` spans both periods and can therefore include a category that was spent on last period and abandoned this one — which the first list cannot contain, and which is among the more useful things a comparison has to say.

The home-screen widget adds the only other place data leaves the ledger, and it is deliberately the narrowest boundary in the app. A widget runs in its own process at times the app is not alive, so it can never hold the SQLCipher key; instead the app *publishes* what the drawing needs — a flag, one or two ratios, and the current palette's colours — into plain unencrypted `SharedPreferences`, and the widget draws from that alone. Nothing that crosses is an amount, a balance or an account name: `HomeWidgetSnapshot`'s equality is defined so that a small month and a huge one with the same split compare equal, which is the proof that only the ratio survives the trip. The widget therefore shows the shape of a month and tells a stranger glancing at the phone nothing at all. The figure is redrawn natively in Kotlin rather than rendered from Flutter, because a widget resized or restored by Android has no live engine to render with; `flow_shape_geometry_ports_test.dart` reads both files as text and fails, naming the constant, when the two copies of the geometry drift apart.

The pure-Dart domain layer owns exact minor-unit money, parser definitions, match scoring, and reversible reconciliation decisions. The data layer persists accounts, independent multi-source mappings, immutable evidence, categories, debts, decisions, and canonical transactions in SQLCipher. UI code consumes canonical state and never promotes an Android callback directly into the ledger.

The Android listener applies the explicit package allowlist before capture. It extracts public `StatusBarNotification`, content, messaging, action, ranking, channel, grouping, and lifecycle fields into a versioned snapshot. The snapshot is AES-GCM encrypted under Android Keystore before entering a bounded durable queue. Flutter uses peek, idempotent ledger commit, then acknowledgement, so process death can cause a safe replay but not silent loss.
