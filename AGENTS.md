# Project rules

Read `PROJECT_STATUS.md` before starting substantial work. It is the durable
handoff for the current shipped version, architecture, verification workflow,
release conventions, and known risks. Update it whenever those facts change.

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
