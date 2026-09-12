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

Spending is not the only way money leaves an account. A loan made, a borrowing repaid and a transfer into savings all reduce it without being spending, and a figure that ignores any of them drifts from the balances by exactly the amount ignored. `homeFigures` in `lib/features/dashboard/home_savings.dart` is the single assembly of those numbers, and it works every one of them out over one window — the window it resolves itself, from `HomePeriod` and the `now` it was given. Earnings and spending used to come from the controller's `dashboard` instead, which resolves a window of its own against the clock when its cache is filled and holds it until a reload; that made Home two windows, and it printed the mixture under one month's name whenever they differed. The shared rules in `lib/app/period_figures.dart` answer all of it now, and the category breakdown beneath the shape is asked for the same window through `categorySpendingIn` rather than taken from the dashboard's cache -- Home reads no dashboard at all.

Debts carry two orthogonal facts: `direction` (which way the money moved) and `held` (whether it was ever the user's). Their three combinations are `DebtKind.lent`, `borrowed` and `holding`. Held money is stored as a borrowing that was never the user's rather than as a third `direction` value, because widening that column's CHECK constraint requires rebuilding the `debts` table and `transactions.debt_id` cascades on delete. Held money is subtracted from available-to-spend, and both its legs are excluded from the dashboard flow.

Two smaller contracts hold the UI together. A Review rule carries a list of `ReviewAction`s rather than one action plus an optional second, because its answers need different things — an account, a direction, nothing — and one set of flags on the rule meant the question that most needed a third answer could not have one. And a stored view preference notifies when it changes: writing to the ledger without announcing it left screens already built showing the previous choice, which made a setting look as though it did nothing.

Two contracts govern how categories are drawn. A category's colour comes from `CategoryTones`, keyed to the ledger's own category order rather than to its position in the list being drawn, because that position moves whenever spending does and a category that changes colour between two months cannot be recognised across them. And `SpendingAnalytics` exposes two lists rather than one: `categories` is this period's spending and answers "where your money went", while `categoryChanges` spans both periods and can therefore include a category that was spent on last period and abandoned this one — which the first list cannot contain, and which is among the more useful things a comparison has to say.

Every figure above is derived from another figure, which is why one is not. `LedgerSnapshot.accountRunningBalances` walks the entries oldest-first from each account's opening balance and records what each account held after each entry that touched it, and the entry screen prints that either side of the amount. It is the only number in the app an owner can check from outside, against a bank statement, without trusting a sum SpendWise made — so it is built to reconcile by construction rather than by agreement: the last value for an account is `accountBalanceMinor` for that account, a test holds the two together, and the figure before is the figure after less what the entry did. The walk runs once per snapshot, not per row, because it is over every entry there is.

A loan is settled by attaching the entry that repaid it, not by recording an amount beside it. The ledger takes an entry out of the month by its `debt_id` and by nothing else, so a settlement with no entry attached — which is the right record for cash, since banknotes send no alert — leaves a bank repayment counted as income while the loan reads as closed. `settleDebt` therefore takes an optional transaction id, and every screen that can see a candidate offers it: the entry suggests the loan it looks like, the loan lists the entries that look like it, and Review asks per loan before it asks anything else. Matching is deliberately narrow and never acts alone — right direction, right currency, not before the loan existed, never more than is still out, and then either the counterparty's name in the narration or exactly the outstanding amount — because a loan the owner believes is closed is money they will never ask for again.

Cash is the one transfer the app asserts from a single alert rather than by pairing two. Every other transfer between the owner's accounts is inferred by matching a debit on one against a credit on the other; a wallet full of notes never sends a notification, so the opposing leg cannot exist and waiting for it would mean waiting forever. A withdrawal therefore becomes a transfer from the bank into a cash account, and the money is only spent when the owner says what it bought.

Two things guard that. The first is a routing stamp, `cash_routing_from`, written once and never moved: reconciliation rebuilds automatic transactions from stored evidence on every run, so without it the first run after this arrived would reach back through every withdrawal ever made and call the lot of it money still in a pocket. It cannot be the cash account's own creation time, because that account is made while reconciling the very withdrawal that calls for it. The second is that cash is excluded from `AccountRouter`: it has no source app and no account number, so a name match is the only way an alert could ever reach it, and an account called "Cash" otherwise captures the phrase "cash withdrawn" and swallows the withdrawal that was meant to leave the bank.

Nothing automatic ever moves money *out* of cash. Spending it, holding it for somebody, lending it — those are the owner's to record, because nothing observable happens when a banknote changes hands.

The home-screen widget adds the only other place data leaves the ledger, and it is deliberately the narrowest boundary in the app. A widget runs in its own process at times the app is not alive, so it can never hold the SQLCipher key; instead the app *publishes* what the drawing needs — a flag, one or two ratios, and the current palette's colours — into plain unencrypted `SharedPreferences`, and the widget draws from that alone. Nothing that crosses is an amount, a balance or an account name: `HomeWidgetSnapshot`'s equality is defined so that a small month and a huge one with the same split compare equal, which is the proof that only the ratio survives the trip. The widget therefore shows the shape of a month and tells a stranger glancing at the phone nothing at all. The figure is redrawn natively in Kotlin rather than rendered from Flutter, because a widget resized or restored by Android has no live engine to render with; `flow_shape_geometry_ports_test.dart` reads both files as text and fails, naming the constant, when the two copies of the geometry drift apart.

The pure-Dart domain layer owns exact minor-unit money, parser definitions, match scoring, and reversible reconciliation decisions. The data layer persists accounts, independent multi-source mappings, immutable evidence, categories, debts, decisions, and canonical transactions in SQLCipher. UI code consumes canonical state and never promotes an Android callback directly into the ledger.

The Android listener applies the explicit package allowlist before capture. It extracts public `StatusBarNotification`, content, messaging, action, ranking, channel, grouping, and lifecycle fields into a versioned snapshot. The snapshot is AES-GCM encrypted under Android Keystore before entering a bounded durable queue. Flutter uses peek, idempotent ledger commit, then acknowledgement, so process death can cause a safe replay but not silent loss.
