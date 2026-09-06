# Project rules

Read `PROJECT_STATUS.md` before starting substantial work. It is the durable
handoff for the current shipped version, architecture, verification workflow,
release conventions, and known risks. Update it whenever those facts change.

## Finishing a change

A behaviour change is not finished when the code works. Everything below
describes the app to somebody, and a description that has quietly gone stale
is worse than none — it is the app telling the user something untrue.

Before calling a change done, walk this list and update whatever the change
actually invalidated. Say which ones you checked and which needed nothing;
"I updated the docs" is not a report.

- **The in-app manual** — `lib/features/help/help_topics.dart`. Settings →
  How SpendWise works. Each chapter's `brief` is also the text copied by the
  "copy prompt" button, so a person can ask an AI about the app. That makes a
  stale `brief` doubly wrong: it misleads the reader *and* it is handed to a
  model as fact. If you changed what a screen offers, what an action is
  called, or what a decision means, the chapter that covers it is stale.
- **Onboarding** — `lib/features/onboarding/`. It promises a specific first
  run. Changing account setup, permissions, or the golden path changes what
  it should promise. It is held to a word budget by a test; keep it.
- **The guided tour** — `lib/features/tour/spotlight.dart`. Its stops point at
  real widgets. Moving or renaming a control breaks the stop that names it.
- **`README.md`** — the public description, its screenshots, and
  `assets/screenshots/how-it-reads.svg`. A UI change that alters what a
  screenshot shows means the screenshots are stale, not just the prose.
- **`ARCHITECTURE.md`** — invariants and data flow. Update it when a layer
  boundary, a table, or the path a notification takes changes.
- **`PROJECT_STATUS.md`** — shipped version, verification workflow, release
  conventions, known risks.
- **`SECURITY.md`** — only when the trust boundary or threat model moves.
- **Tests** — a test asserting the old copy or the old contract is not "a
  test to fix"; it is the old contract, and it needs rewriting to state the
  new one deliberately. Never edit an assertion merely to make it pass.

**Installing on the device.** Build with
`flutter build apk --release --split-per-abi`. A plain `--release` writes only
the universal APK and leaves the previous build's per-ABI files in place, so
`adb install -r .../app-arm64-v8a-release.apk` will happily install a stale
binary and report `Success`. Delete the per-ABI APKs first, then check the
file's mtime is later than the commit before installing, and check the
package's `lastUpdateTime` after. `Success` alone proves nothing about *what*
was installed.

**Screenshots.** Take them from the sandbox install with demo data on
(`local/sandbox-flavour.patch`, a separate application id), never from the
real app — see the device rules below. Frame them with
`scripts/frame.py`-style device framing so they match the existing set. Never
publish a screenshot you have not looked at.

**Demo data** (`seedDemoData` in `lib/data/local_ledger.dart`) is what those
screenshots show, so it is presentation, not test scaffolding. Keep its
balances deliberately unequal: Accounts draws every account to scale, and a
seed with similar balances demonstrates none of that.

## Connected-device data safety

Treat every connected physical Android device as containing irreplaceable real user data.

- Never uninstall SpendWise, run `adb shell pm clear`, clear storage/cache, reset onboarding, erase the ledger, remove secure-storage keys, delete app files, enable demo data, or otherwise wipe/replace device state.
- Never create, edit, delete, import, reconcile, archive, restore, or recategorize real records on a connected device merely to test a feature. Do not toggle the user's notification sources or account assignments for testing.
- Use in-memory databases, synthetic fixtures, widget tests, or a separately identified emulator/test application for any test that mutates data.
- Read-only navigation, screenshots, UI hierarchy inspection, logs, package metadata, and permission inspection are allowed. Stop before any destructive or record-changing confirmation.
- Device upgrades must preserve data: verify analyzer/tests/build first, confirm the target package is `com.spendwise.app`, never downgrade, and install only with `adb install -r`. Do not use uninstall/reinstall as a troubleshooting step.
- Before installing a build that changes persistence, encryption, migrations, or account semantics, add and pass migration/regression coverage proving existing data remains readable and unchanged. If preservation is uncertain, do not install it on the physical device.
- Never copy real financial data, notification contents, database files, keys, screenshots containing sensitive records, or exports outside the device unless the user explicitly requests that exact operation.

When a device-only verification would require changing user data, skip that action and report the limitation instead.
