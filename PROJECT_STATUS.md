# SpendWise project handoff

Last updated: 2026-09-08

## Current release

- Version: `0.9.25+40`
- Android package: `com.spendwise.app` — keep this stable so upgrades retain data.
- Public repository: <https://github.com/abdullah270602/spendwise-local>
- Latest release: <https://github.com/abdullah270602/spendwise-local/releases/tag/v0.9.25>
- Shipped APK is the optimized split-per-ABI release build, not a Flutter debug
  build. Build with `flutter build apk --release --split-per-abi`; a plain
  `--release` writes only the universal APK and leaves the per-ABI files from
  the *previous* build sitting in the output directory, which is an easy way to
  install a stale binary and believe it is current. Check the APK's mtime
  against the commit before installing.
- Split-per-ABI adds 2000 to the version code for arm64: `40` becomes `2040`.
- Installed on the connected Pixel 9 at this version, with `adb install -r`.

## Known reliability issues

**Capture silently stopping — root-caused.** Symptom: accounts update but
nothing reaches the Ledger, with `outcome=SKIPPED (not configured)` and
`drain peeked 0` in logcat. Capture is gated natively by
`sourceStore.isConfigured(pkg)` in `SpendWiseNotificationListenerService.kt`,
and that list is written *only* by `setNotificationSources` / `setSourceEnabled`
from Settings → Notification sources. Anything that clears it — including
`NotificationBridge().clear()` — silently disables all capture, and sources do
**not** re-attach themselves. Recovery is re-enabling the apps in Settings →
Notification sources. Never call `clear()` against a real install.

**Historic (fixed at `0.9.6`):** manual "scan tray" froze the app because
`scanCurrentTray()` blocked on the main thread.

Detail on that fix: `SpendWiseNotificationListenerService.scanCurrentTray()`
blocked with `writer.submit(...).get(15, TimeUnit.SECONDS)`, and that call ran
directly on Android's main thread because the `com.spendwise.app/notifications`
`MethodChannel` had no background `TaskQueue`. `MainActivity.kt` now creates
the channel with `BinaryMessenger.makeBackgroundTaskQueue()`, which also moves
`listNotificationSources()`'s per-app icon rendering off the main thread —
that heavy call ran during startup via `_refreshPlatform()` and was a second
contributor to the cold-start freeze. `SpendWiseController._drainNotificationQueue()`
also now yields every 25 events so a large backlog (e.g. accumulated while the
old bug was blocking drains) can't hold the Dart UI isolate in one unbroken
synchronous stretch.

Still open / not yet root-caused: background auto-capture occasionally missing
events entirely, with zero trace even in Review. Current suspicion is
`SpendWiseNotificationListenerService.captureNow()` swallowing an extraction
exception via `runCatching { }.getOrNull() ?: return FAILED` with no logging —
needs `adb logcat` captured live during a reproduction to confirm (no device
was connected during this investigation). Consider adding a lightweight
"last capture failure reason" field to ingestion health so this is diagnosable
without logcat next time.

## Dev environment note (resolved)

`flutter test` and `flutter build apk` previously failed during a "native
assets" build-hook step for the `objective_c` package (pulled in transitively
by `path_provider_foundation`, unused on this Android-only app), because the
Flutter SDK was installed at `C:\Users\Your Full Name\...` — a path
containing a space — and the native-assets hook runner doesn't quote it when
shelling out to `dart compile kernel`. `flutter analyze` was never affected
(it doesn't build native assets).

Fixed by relocating the Flutter SDK to `C:\dev\flutter` (a straight file copy
of the existing install, so no re-download) and pointing the User `PATH` at
`C:\dev\flutter\bin` instead of the old `AppData\Local\Programs\flutter\bin`
entry. The old install was left in place, untouched, in case anything still
references it. After the move: `flutter test` (79/79) and
`flutter build apk --release` both succeed again. If a fresh terminal still
resolves the old path, check `[Environment]::GetEnvironmentVariable('Path','User')`
for a stale `AppData\Local\Programs\flutter\bin` entry — it should only list
`C:\dev\flutter\bin` now.

Version names must continue to start with `0.` until the user explicitly changes
that policy. Increment both the semantic patch version and Android build number
for every installed or published build.

## Product and privacy boundaries

SpendWise is an Android-first, local-only Flutter finance ledger. Raw
notifications and statement rows are evidence; canonical transactions are the
reconciled ledger. There is no backend, authentication, analytics, telemetry,
advertising, remote crash reporting, or implicit network use. The Android
manifest must not request `INTERNET`.

The SQLite ledger is SQLCipher-encrypted and its key is held through secure
storage/Android Keystore. Native notification staging is encrypted separately.
Do not weaken either boundary. BYOK AI remains out of the shipped core.

Never commit real statements, notification bodies, account identifiers,
financial values, database files, keys, device screenshots containing financial
information, or temporary probes containing private paths. Tests use synthetic
fixtures only.

## Connected-device rule

The physical Pixel contains irreplaceable user data. Follow the full safety rules
in `AGENTS.md`. In particular:

- Never uninstall SpendWise or clear its storage/cache.
- Never mutate real accounts, sources, transactions, categories, imports, or
  notification evidence for testing.
- Read-only launch/navigation/package inspection is allowed.
- Verify analysis, tests, package ID, version code, permissions, and build before
  a device upgrade.
- Upgrade only with `adb install -r`; never use uninstall/reinstall.

## Shipped functionality

- Premium dark Material 3 shell: Home, Ledger, Review, Accounts, Settings.
- Android `NotificationListenerService` ingestion with encrypted durable queue,
  configured global source selection/search, and notification-tray recovery.
- Deterministic Pakistani banking/SMS parsing and evidence reconciliation,
  including duplicate legs and internal transfers.
- Manual transactions, transaction correction/deletion, review actions, account
  creation/edit/archive/restore, savings accounts, and current-balance correction.
- Three debt stories: lent out, borrowed, and **held for someone else** — money
  that landed in an account and was never the user's. Held money is subtracted
  from available-to-spend and excluded from both sides of Home's flow; borrowed
  money is not, because it is spendable until repaid. `changeDebtKind` re-files
  history recorded before the third story existed.
- Home reports the change in the spendable balance: what came in, minus
  everything that left. Loans made, borrowings repaid and transfers into
  savings all leave without being spending, and each is counted.
- Home's appearance is chosen through one shared pattern — a pinned live
  preview of Home drawn by Home's own widgets, with plain option rows beneath.
  It covers the window ("How much time Home shows"), savings (two independent
  questions: whether saving comes out of the figure, and what line sits
  underneath), and colour.
- Deleted transactions stay deleted: `deleted_transactions` tombstones survive
  the reconciler's rebuild of automatic entries.
- Review asks one question per app, covering everything that app failed to
  deliver whichever way it failed, with the same three answers each time:
  attach to an account, file as transactions, or drop. Dropping is a soft flag
  and is the only answer that offers Undo, restoring each alert's exact prior
  parse status. The answer is stated where the question was rather than in a
  toast, and clears itself.
- The category breakdown on Home is a choice: every category, the five biggest
  with the rest folded into one line, or none at all. The fold keeps the
  remainder because the bar is drawn to true proportion. It defaults to none:
  Home's answer is the shape and the two figures, and the breakdown is turned
  on by whoever wants it rather than met on a first run.
- Motion: the ribbon pours downward on open and on returning to Home, travels
  between proportions rather than jumping when figures change, and answers a
  tap with a two-pixel damped wobble. Reduced motion turns all of it off.
- `Adjust balance` changes only an account's baseline by the difference; it keeps
  existing transactions and avoids fake income/spending.
- CSV/XLS/XLSX statement import with preview, multi-file/multi-sheet selection,
  atomic commit, Meezan-style metadata/header recognition, Excel serial dates,
  split Debit/Credit handling, and occurrence-aware cross-file deduplication.
- Local deterministic categorization including entertainment, subscriptions,
  dining, groceries, bills/utilities, fees, cash withdrawal, health, education,
  travel, insurance, government/taxes, income, and transfers.
- Insights is three questions, each answered separately and each able to be
  turned off: **over time** (the spine of days), **where your money went**
  (bars, the Chronograph dial, or the Mixing Desk fader bank), and **what
  changed** against the previous period (the Seismograph trace or the Gate's
  corridor). "What changed" is off by default — it is the only section that
  makes a claim about the past rather than reporting the present.
- Insights' two day windows are calendar-aligned, not rolling: **this week**
  is Monday to today and **this month** is the 1st to today. The comparison
  window is cut to the same number of elapsed days, so the 3rd of a month is
  measured against the first three days of the previous month rather than
  against all thirty-one. Rolling windows named "This month" would have been
  showing most of the previous month under this month's name.
- The period is chosen through a chooser with a live preview, not a segmented
  control. Four segments named honestly want 424 logical pixels and a 360px
  phone has 316; the old four-way toggle had been overflowing a real phone by
  108px unnoticed, because every widget test ran at the 800x600 default.
- A category's colour is keyed to the ledger's own category order
  (`CategoryTones`, `lib/app/category_tones.dart`), not to its position in
  whatever list is being drawn. Position moved every time spending did, so a
  category changed colour between one period and the next, and two screens
  showing the same month could disagree.
- Selecting a category no longer hides the breakdown. The totals behind it are
  computed across every category regardless of the filter, so the picture can
  stay on screen, dimmed, at the moment somebody is examining one part of it.
- Appearance is one door in Settings covering Home, Insights and colour.
  Colour is no longer filed under "Home": it repaints the whole app and only
  lived there because that was the section that existed.
- Onboarding asks for the account holder's name on a fifth card, optional and
  visibly so — the button reads "Skip for now" until something is typed. Own
  names feed `OwnIdentity`, which is how the reconciler recognises a transfer
  between the user's own accounts. Asking at setup matters because
  reconciliation runs on ingest and skips anything already resolved by hand:
  a transfer misfiled while this was blank and then corrected manually can
  never be re-derived correctly, whatever is typed later.
- `setOwnNames` now reconciles. It previously wrote the names and stopped, so
  nothing changed until the next bank alert happened to arrive and the setting
  looked broken for the whole gap.
- The spending report opens with one of the app's own drawings rather than a
  layout invented for paper: **the ribbon** (Home's flow shape), **the dial**
  (the Chronograph), **the desk** (the Mixing Desk) or **the trace** (the
  Seismograph against the previous period). Each carries the same summary and
  the same register beneath, so nothing is lost by preferring one, and the
  choice defaults to whatever Insights is already drawing. Drawing them for
  paper was not a recolour: the desk's two-tone bevel inverts on white and
  carries its machined feel in line weight instead, and every tone is relit by
  `paperTone` and held to a measured contrast minimum by test.
- The report is one `pw.MultiPage`. It was a fixed `pw.Page` bounded only by
  curation, and a plain `Page` does not clip -- a busy month could push content
  past the physical edge, invisible rather than ugly, on a document whose whole
  job is to be a record.
- Settings, Appearance, Export and Notification sources keep the Material
  `Card`/`ListTile` look, deliberately, while every other screen is flat
  hairlines. They were redrawn flat in one pass and the owner asked for the
  boxy version back after seeing it on the device. `AGENTS.md` says not to
  redo it; a review will keep proposing it.
- The transaction details screen and the debt sheets follow the same rule, and
  all three debt stories are offered where the record is made. Deleting from a
  transaction's own screen offers the same Undo the Review inbox does, and
  "Not a loan" — which discards a debt's whole history — asks first.
- Both empty states say so when notification access is granted but every
  source is switched off, and offer the way back.
  `lib/features/capture/capture_state.dart` owns that fact, because Home and
  the Ledger both report it and a second copy of the wording is a second
  chance for them to disagree.
- A register row prints a sign and carries one merged `Semantics` label, so a
  screen reader hears whether money came in or went out. It had encoded that
  in colour alone.
- Erasing all local data is four gates rather than a dialog: the PIN if one is
  set (PIN only -- a fingerprint can be used on somebody asleep or unwilling),
  a full screen rather than a dismissable dialog, the word ERASE typed out,
  and a thirty-second countdown that leaving the screen or closing the app
  cancels. A pending erase is never resumed on next launch: that would take
  the data of somebody who had already changed their mind.
- An Android home-screen widget draws the ribbon and nothing else: no digits,
  no percentage, no words. It follows Home's own savings style, so the two
  objects cannot disagree about the same shape, and it is resizable, falling
  back to a flat proportional bar where a cell is too short for a curve to
  read as one. The background is transparent; every filled shape carries a
  two-tone hairline, because a dark outline vanishes on a black wallpaper and
  a light one vanishes on white, and both are drawn on every edge so whichever
  ring loses contrast locally the other holds the boundary.
- Cash is an account. A withdrawal is recognised structurally -- a withdrawal
  verb and a cash or ATM marker close together, and nothing that reads as a
  merchant -- and becomes a transfer from the bank into a cash bucket rather
  than an expense, so the money is only spent when the owner records what it
  bought. Nothing automatic ever takes money out of cash. The bucket is made
  when setup finishes, or on the first withdrawal if setup was skipped, and a
  `cash_routing_from` stamp keeps every withdrawal made before the feature
  existed exactly as it was filed.
- Local export, insights, notification-source health, demo-data controls, and
  Settings version/build display with a user-invoked GitHub link.

## Performance state

Release `0.9.6` replaced the shell's eager `IndexedStack` with page-isolated
navigation and caches derived Accounts/Transactions/Dashboard/Review view data
until `_reload()` invalidates it. This prevents tab taps from rebuilding all
destinations and eliminates repeated synchronous SQLite/evidence queries.

Measured on the connected Pixel 9:

- Previous debug APK cold start: approximately `2621–2826 ms`.
- Optimized release APK cold start: approximately `782–831 ms`.
- Improvement: roughly 70%.

Do not publish debug APKs as releases. Preserve the lazy page isolation and cache
invalidation behavior when changing the shell/controller.

## Verification baseline

At `0.9.25`, the analyzer is clean and all 709 tests pass. Before shipping:

1. Run `dart format` on changed Dart files.
2. Run `flutter analyze --no-pub`.
3. Run focused tests while iterating, then `flutter test --no-pub`.
4. Build with `flutter build apk --release --split-per-abi`, after deleting the
   previous per-ABI APKs so a stale file cannot be installed by mistake.
5. Inspect the APK with `aapt dump badging`; require package
   `com.spendwise.app`, the intended higher version code, and no `INTERNET`.
6. Hash the APK with SHA-256 and include it in release notes.
7. Commit locally, push `main`, and publish the exact verified `app-release.apk`.
8. If explicitly requested, upgrade the connected device only with
   `adb install -r`, then verify installed package metadata.

The local toolchain previously used Flutter 3.47.1 / Dart 3.13.1, Android SDK at
`C:\Android\Sdk`, and Android Studio's bundled JDK. Agents should discover the
current configured paths rather than assume another user's home directory.

## Working rules learned the hard way

- **A stored setting must notify.** `setViewPreference` wrote to the ledger and
  told nobody, so screens already built kept the previous choice and the whole
  setting looked broken. Every earlier setting had masked this by also calling
  something that notified.
- **Test the screen, not just the helper.** The category fold was unit-tested
  and its preview was widget-tested, and both passed while the feature did
  nothing on Home. A setting is only real if the screen it configures obeys it.
- **Reduced motion is not automatic.** A raw `TweenAnimationBuilder` gets none
  of the help Flutter gives the `Animated*` widgets; it has to be honoured by
  hand or it is not honoured at all.
- **Test at the size of a phone.** Every widget test ran at the 800x600
  default, where a header can hold almost anything, and the Insights period
  toggle had been overflowing a real 360px device by 108 pixels with nothing
  to catch it. A layout assertion is worth only as much as the viewport it
  was made in.
- **A label is a claim about the data.** Renaming a rolling thirty-day window
  to "This month" is not a copy change; it is either a lie or a reason to
  change the window. The window was changed.
- **A test double that throws is doing its job.** Six fakes refused a member
  the app had never asked them for, which is how a new dependency announces
  itself. Widening one of them from the plain interface to the advanced one
  silently reroutes every other call away from the safe defaults a dozen
  unrelated tests are relying on — give the new need its own fake instead.
- **Every figure needs the same exclusions.** The report counted debt
  movements as ordinary income and spending for as long as it existed, while
  Home and Insights had always left them out: money held for somebody else
  was counted twice, once arriving and once leaving, and "Transfer" could
  outrank every real category on a page meant to be handed to someone. The
  ledger knew all along -- `TransactionViewData.isLoanMovement` -- and the
  report simply never asked. When a figure excludes something the list beside
  it still shows, say so on the page; otherwise the two disagree in silence.
- **A Container with an `alignment` and no width takes every pixel it is
  offered.** Centring a segmented control's labels that way turned three
  segments into three stacked full-width rows on a real phone. The test that
  should have caught it asserted the control's *width*, which a full-width
  block does not violate. Assert the dimension that can actually go wrong.
- **Text scale is a test dimension, and it was never set.** The suite pinned
  the screen size and let the font size default, so a whole class stayed
  invisible: at `textScaleFactor` 2.0 the committed suites produced 43
  overflows across seven widgets. `platformDispatcher.textScaleFactorTestValue`
  turns the existing tests into the detector.
- **A guideline is not a decision.** `ViewToggle` is knowingly under the 48dp
  tap-target minimum: raised to 48 it read as a slab in a header, and the
  owner reverted it on the device. The test now pins it *compact* and says
  why, because a test asserting a guideline the product has deliberately
  declined is a test that lies.
- **Naming a thing can rewire the app around it.** Creating an account called
  "Cash" made `AccountRouter` match the word "cash" in "cash withdrawn" and
  attribute the withdrawal to the cash account itself rather than the bank it
  left. Anything matched by name has to be asked whether it should be
  matchable at all.
- **A row that always exists is a row that can never be absent.** Seven places
  ask `accounts.isEmpty` to decide whether the owner has set anything up --
  onboarding's "add your first account" among them. A cash bucket present
  from the first launch answers all seven "yes" forever, and a new arrival is
  never asked for their bank. Found by a Review test looking for a message
  that had quietly stopped appearing.
- **The escape sequence is not the escape sequence.** A Dart regex written
  through a shell heredoc turned every `\b` into a literal backspace byte.
  The pattern compiled and matched nothing. This is written in the project's
  own notes and was walked into anyway: write the script to a file.
- **A consistency finding is not automatically a defect.** Four screens using
  a different vocabulary from the rest of the app reads as an oversight and
  was reported as one; unified, it turned out the owner preferred the
  original. Taste questions go to the person whose app it is before a sweep,
  not after.
- **Percentages rank the wrong things.** A category that went from 350 to 900
  has risen further in percent than one that rose by 6,500 rupees, and only
  one of those belongs at the top of a list. Order by money moved, and gate
  "did this matter" on an absolute floor as well as a percentage.

## Open work

- **The review receipt understates when alerts merge.** `fileAlerts` returns
  a count that `applyReviewDecision` still discards, so the screen measures
  the ledger either side of an answer instead. If reconciliation merges two
  alerts into one entry the receipt says "1 of 2". It can never overstate,
  which was the defect; closing it properly means widening
  `applyReviewDecision` to `Future<int>` across the view model, the
  controller and every test fake.
- **Every write re-reads the whole ledger on the UI isolate.**
  `SpendWiseController.transactions` runs a three-way SQLite join per
  transaction, and the shell rebuilds every review rule inside an
  `AnimatedBuilder` for a badge count. Filing one review costs roughly a
  thousand queries. This is the 500-transaction question and it is not yet
  answered.
- **Two widget contracts are narrower than their designs.** The Chronograph's
  hub cannot name the period because the period is not passed to it, and the
  Mixing Desk cannot draw dead channels — a channel that exists with nothing
  spent on it this period — because it receives only the active categories.
  `CategoryTones` already holds the full list; it just does not expose it.
  Until then the desk's channel numbers skip.
- **Screenshots are stale.** `assets/screenshots/*` still show the pre-`0.9.8`
  Home and Accounts, including the retired "TOTAL TRACKED" and
  "HELD BACK · SAVINGS" labels. Retake from the sandbox install with demo data
  (`local/sandbox-flavour.patch`); never from the real app.
- **CSV/XLS import is slated for removal.** The user has asked for the whole
  import path to be carved out, along with the orphaned `csv_mappings`,
  `csv.user-mapping` and the dead `parser_definitions` table.
- **Home's wording.** "Available" reads as a balance when it is a change over
  the selected window, and Accounts legitimately differs from it by whatever
  was carried in from before that window. The agreed fix is to show both
  figures on Home rather than to reword one of them; not yet built.

## Important known risk

The Android `release` build currently uses the local debug signing configuration
in `android/app/build.gradle.kts`. That preserves upgrade compatibility with the
APK already installed on the Pixel, but it is not suitable as a permanent public
release-signing strategy. Do not silently replace or rotate this signing key:
Android would reject the update and the local-only data could become stranded.
A future signing migration must be explicitly designed, tested, backed up, and
coordinated with the user before broader distribution.

Owning a matching web domain is not required. The visible app name, website, and
repository can change later without affecting data, provided the Android package
ID and compatible signing lineage remain stable.

## Working conventions

- The user prefers implementation over plans and wants frequent concise status
  updates during longer operations.
- Commit completed work locally and keep the public repository/releases current.
- Prefer a small complete feature with regression coverage over broad scaffolding.
- Verify by exit code, never by grepping command output: a grep that fails to
  match reads exactly like a clean run.
- The user requires explicit approval before pushing or publishing a release.
- Preserve the established near-black/navy UI, restrained green accent, compact
  financial hierarchy, and the line `Private. Local. Yours.`
