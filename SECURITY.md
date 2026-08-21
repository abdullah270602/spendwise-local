# Security model

SpendWise has no backend, cloud account, telemetry, analytics, advertising, remote crash reporter, or Android `INTERNET` permission. Ordinary notification processing, parsing, reconciliation, analytics, CSV import, and storage remain on the device.

The ledger uses SQLCipher. Its random 256-bit key is stored through Keystore-backed Android secure storage. Notification snapshots captured while Flutter is stopped use a separate, non-exportable Android Keystore AES-GCM key. Android backup, device transfer extraction, and cleartext network traffic are disabled. Sensitive payloads are not written to application logs.

CSV and JSON exports are deliberately plaintext and are created only after an explicit user action through Android's document picker. The export screen warns about this boundary. Treat exported files as sensitive.

The current V1 does not include cloud sync or AI calls. BYOK AI is intentionally omitted from the core ledger; a future implementation must show the exact redacted payload and require confirmation for every request.

These protections reduce offline extraction risk on a locked device. They do not protect an already-unlocked compromised phone, a rooted attacker, malicious accessibility software, screenshots, or plaintext files the user exports.

To report a vulnerability, open a private security advisory on the project repository when available. Do not include real financial notification content or secrets in a public issue.
