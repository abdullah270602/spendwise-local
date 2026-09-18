# Google Play submission material

Working copy of everything the Console asks for in prose. Kept in the
repository because it has to stay true as the app changes: every claim below
is checkable against the code, and a claim that stops being true is a policy
problem, not a copy problem.

Nothing here is secret. The keystore and its passwords are not in this
repository and must never be (see *Release signing* in `PROJECT_STATUS.md`).

---

## 1. Notification access declaration

The single item most likely to decide the review. Play scrutinises
`BIND_NOTIFICATION_LISTENER_SERVICE` because it can read the content of every
notification on the device.

### Why the app needs it — core functionality

> SpendWise is a personal-finance ledger that builds a record of the user's own
> spending from the transaction alerts their bank already sends them. Reading
> those notifications is not an enhancement to the app: it is the entire
> function. Without notification access, SpendWise has nothing to record, and
> the only alternative is for the user to type every transaction in by hand —
> which is the problem the app exists to solve.
>
> The user chooses which apps may be read, one at a time, in Settings →
> Notification sources. No notification is read from an app the user has not
> explicitly enabled. Notifications that do not describe a monetary movement —
> one-time passcodes, delivery updates, marketing — are discarded rather than
> stored as transactions.
>
> Everything happens on the device. SpendWise does not request the `INTERNET`
> permission and contains no backend client, telemetry, analytics, advertising,
> crash reporting or AI provider, so notification content cannot leave the
> phone even in principle.

### Why not a less sensitive alternative

Worth stating explicitly, because a reviewer will ask it:

- **SMS permissions were deliberately not used.** SpendWise does not request
  `READ_SMS`, `RECEIVE_SMS` or any call-log permission. Where a bank sends an
  SMS, SpendWise sees only the notification the user's messaging app posts, and
  only if that app is enabled as a source. Notification access is the *less*
  privileged route to the same information.
- **There is no bank API to use instead.** The app is built for markets —
  Pakistan among them — where consumer open-banking APIs are not generally
  available, and where the bank's alert is the only machine-readable record a
  person has of their own transaction.
- **Manual entry is the alternative and it is the problem.** The app's value is
  precisely that the ledger builds itself.

### Scope, stated plainly

- Read only. SpendWise never posts, dismisses, or acts on a notification.
- Only from user-enabled source apps.
- Content is parsed on-device into an amount, direction, date, counterparty and
  reference; the raw text is retained as evidence for the entry so the user can
  check any figure against what the bank actually said.
- Revocable at any time in Android settings; individual sources can be switched
  off inside the app; **Erase all local data** removes everything.

### Demo video — what it must show

Reviewers commonly want a screen recording. It should show, in one take:

1. Settings → Notification sources, enabling **one** named bank app.
2. The Android permission screen where notification access is granted.
3. A bank alert arriving.
4. That alert becoming a ledger entry, with the raw text visible as evidence on
   the transaction detail screen.
5. Settings → **Erase all local data**, to show the user can take it all back.

Use the sandbox install with demo data — never a real ledger.

---

## 2. Data safety form

The answers, with the reason each one is defensible:

| Question | Answer | Why |
|---|---|---|
| Does your app collect or share any user data? | **No** | No `INTERNET` permission. Data cannot leave the device. |
| Is all user data encrypted in transit? | N/A | There is no transit. |
| Do you provide a way to delete data? | **Yes** | Settings → Erase all local data, and uninstalling. |
| Third-party SDKs collecting data | **None** | No analytics, ads, or crash reporting. |

"Collect" in Play's definition means transmission off the device. SpendWise
stores a great deal on the device and transmits none of it, which is exactly
the distinction the form draws.

A user-initiated CSV/JSON export writes through Android's system document
picker to a location the user chooses. That is the user moving their own data,
not the app collecting it.

---

## 3. Store listing copy

### App name

SpendWise

### Short description (80 characters max)

> Your bank already tells you everything. SpendWise keeps the record.

*(66 characters.)*

### Full description (4000 characters max)

> SpendWise turns the transaction alerts your bank already sends you into a
> ledger of your own money. No typing every purchase in. No connecting your
> bank account to anything. No account to sign up for.
>
> **It cannot go online.**
>
> SpendWise does not request Android's internet permission. Not "we promise not
> to send your data" — the app is not capable of sending it. There is no
> server, no sign-in, no analytics, no advertising and no crash reporting.
> Your financial history stays on your phone, in an encrypted database, and
> nowhere else.
>
> **How it works**
>
> Choose which apps SpendWise may read — your bank, your wallet, your
> messaging app. When one of them posts an alert about money, SpendWise reads
> the amount, which way it went, and who it was, and files it. You get a
> ledger that keeps itself.
>
> When it is unsure, it asks instead of guessing. When you correct the same
> shop a few times, it learns and stops asking.
>
> **What you get**
>
> • A month at a glance: what arrived, what is still yours, what went
> • Every entry backed by the exact alert it came from, so you can check any
>   figure against what your bank actually said
> • Accounts, balances, and money you are holding for someone else
> • Loans, both directions, including repayment in instalments
> • Categories that learn from your corrections
> • Reports as PDF, and export to CSV or JSON, whenever you want them
> • App lock with PIN or fingerprint
> • Light and dark, and a palette you choose
>
> **Private. Local. Yours.**
>
> The full source code is public at
> github.com/abdullah270602/spendwise-local — including the part that proves
> there is no network permission.

### Category

Finance

### Tags

budget, expense tracker, personal finance, offline, privacy

### Contact email

**TO FILL IN** — Play requires a public contact address on the listing. Decide
whether to use a personal address or a dedicated one before submitting.

### Privacy policy URL

`https://abdullah270602.github.io/spendwise-local/PRIVACY` — live once GitHub
Pages is enabled over `/docs`.

---

## 4. Assets still needed

- **App icon**, 512×512 PNG.
- **Feature graphic**, 1024×500 PNG. No screenshot inside it; it is a banner.
- **Phone screenshots**, 2–8, at least 1080px on the short side. From the
  sandbox install with demo data (`local/sandbox-flavour.patch`), never from a
  real ledger. Candidates: Home with the ribbon, the Ledger, a transaction with
  its evidence, the Review inbox, Insights.
- **Demo video** per section 1.

---

## 5. Open questions for the owner

1. **Contact email** for the listing and the privacy policy.
2. **Does the account need closed testing** before production? Confirm the
   current threshold in the Console. It is calendar time and cannot be
   compressed.
3. **Countries.** Start narrow — Pakistan only — or open?
4. **App name availability** on Play under "SpendWise".
