# SpendWise project handoff

Last updated: 2026-08-22

## Current release

- Version: `0.9.6+21`
- Android package: `com.spendwise.app` — keep this stable so upgrades retain data.
- Public repository: <https://github.com/abdullah270602/spendwise-local>
- Latest release: <https://github.com/abdullah270602/spendwise-local/releases/tag/v0.9.6>
- Shipped APK is now the optimized `app-release.apk`, not a Flutter debug build.
- Latest commit at the time of this handoff: `f4401ab` (`perf: make navigation instant`).
- The connected Pixel 9 was upgraded in place to `0.9.6 (21)` with `adb install -r`.

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

At `0.9.6`, the analyzer was clean and all 78 tests passed. Before shipping:

1. Run `dart format` on changed Dart files.
2. Run `flutter analyze --no-pub`.
3. Run focused tests while iterating, then `flutter test --no-pub`.
4. Build with `flutter build apk --release --no-pub`.
5. Inspect the APK with `aapt dump badging`; require package
   `com.spendwise.app`, the intended higher version code, and no `INTERNET`.
6. Hash the APK with SHA-256 and include it in release notes.
7. Commit locally, push `main`, and publish the exact verified `app-release.apk`.
8. If explicitly requested, upgrade the connected device only with
   `adb install -r`, then verify installed package metadata.

The local toolchain previously used Flutter 3.47.1 / Dart 3.13.1, Android SDK at
`C:\Android\Sdk`, and Android Studio's bundled JDK. Agents should discover the
current configured paths rather than assume another user's home directory.

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
- README cleanup is intentionally deferred unless the user asks to resume it.
- Preserve the established near-black/navy UI, restrained green accent, compact
  financial hierarchy, and the line `Private. Local. Yours.`
