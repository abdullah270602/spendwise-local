# SpendWise project handoff

Last updated: 2026-09-07

## Current release

- Version: `0.9.11+26`
- Android package: `com.spendwise.app` — keep this stable so upgrades retain data.
- Public repository: <https://github.com/abdullah270602/spendwise-local>
- Latest release: <https://github.com/abdullah270602/spendwise-local/releases/tag/v0.9.11>
- Shipped APK is the optimized split-per-ABI release build, not a Flutter debug
  build. Build with `flutter build apk --release --split-per-abi`; a plain
  `--release` writes only the universal APK and leaves the per-ABI files from
  the *previous* build sitting in the output directory, which is an easy way to
  install a stale binary and believe it is current. Check the APK's mtime
  against the commit before installing.
- Split-per-ABI adds 2000 to the version code for arm64: `26` becomes `2026`.
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
- `Adjust balance` changes only an account's baseline by the difference; it keeps
  existing transactions and avoids fake income/spending.
- CSV/XLS/XLSX statement import with preview, multi-file/multi-sheet selection,
  atomic commit, Meezan-style metadata/header recognition, Excel serial dates,
  split Debit/Credit handling, and occurrence-aware cross-file deduplication.
- Local deterministic categorization including entertainment, subscriptions,
  dining, groceries, bills/utilities, fees, cash withdrawal, health, education,
  travel, insurance, government/taxes, income, and transfers.
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

At `0.9.11`, the analyzer is clean and all 364 tests pass. Before shipping:

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

## Open work

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
