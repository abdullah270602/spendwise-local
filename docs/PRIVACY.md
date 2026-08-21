# SpendWise privacy model

SpendWise works without a network connection and does not request Android's `INTERNET` permission.

## Data stored on the device

- Account names and source-package mappings
- Raw notification and CSV evidence
- Parsed event candidates and canonical transactions
- Non-secret local preferences

The main database uses SQLCipher. A random 256-bit database key is generated locally and stored with Android secure storage/Keystore. Notification evidence captured while Flutter is stopped is encrypted field-by-field with AES-GCM under a separate, non-exportable Android Keystore key.

## Data that leaves the device

Nothing is transmitted by SpendWise. The app contains no backend client, telemetry, advertising, analytics, remote crash reporting, or AI provider. A user-initiated CSV export writes only to a location selected through Android's system document picker.

## Controls

- Android notification access can be revoked at any time.
- Individual notification sources must be explicitly enabled.
- “Erase all local data” removes the ledger, journals, secure database key, native queue, and source configuration.
- Android cloud backup and device-transfer extraction are disabled.

## Limits

At-rest encryption and Android's app sandbox reduce exposure from offline extraction or a lost, locked device. They do not defend against malware with sufficient privileges or a person controlling an already-unlocked device.
