# BYOK AI fallback parser — design

Status: proposed. Not yet implemented.

## Problem

SpendWise's deterministic parser (`lib/domain/parsing/notification_parser.dart`)
is deliberately conservative: it only produces a transaction when it finds
exactly one explicit PKR amount and an unambiguous debit/credit signal. Any
notification that doesn't match — an unfamiliar bank's wording, a wallet app's
non-standard format — is stored as evidence but permanently stuck with
`parse_status IN ('review', 'error')`. Today the only paths out of that state
are: map the source to an account (fixes "no account" errors, not text the
parser can't read), or dismiss it (discards it, no transaction is ever
created). For sources whose notification format the deterministic parser
simply doesn't understand, there is no path to an actual ledger entry short
of typing it in manually — which defeats the app's core purpose of turning
notifications into transactions automatically.

## Goal

Let the user optionally configure their own API key against any
OpenAI-compatible chat-completions endpoint. When the deterministic parser
fails to read a notification whose source *is* mapped to an account, send the
notification text to that endpoint as a fallback text-comprehension step. If
the model produces a confident structured extraction, surface it for a single
lightweight confirmation (not a silent auto-post — models can hallucinate
amounts). If the model also fails, the notification falls back to exactly
today's "needs setup" behavior. Nothing about this feature is required to use
the app; it is off by default.

## Non-goals

- **Not a categorizer.** Category assignment keeps its existing
  deterministic keyword-rule engine (`_automaticCategory` /
  `category_rules`). This spec is scoped to amount/direction/counterparty
  extraction only.
- **Not used for account-source mapping.** Notifications from unmapped
  sources fail parsing at the very first check in `parseDetailed()`
  ("No account is mapped to this source") — that is a configuration gap the
  AI cannot resolve without being told which account, and is unrelated to
  whether the text itself is readable. The AI fallback never runs for these.
- **Not agentic.** Single-shot structured extraction per notification, one
  request, no conversation, no tool use, no retries beyond a single timeout.
- **Not a replacement for the deterministic parser.** The deterministic
  parser always runs first and remains the primary path; the AI only sees
  what the deterministic parser already gave up on.

## Trigger and scope

The AI fallback fires when, and only when, `NotificationParser.parseDetailed()`
returns `ParseStatus.unsupported` or `ParseStatus.ambiguous` **and**
`observation.accountId != null` (i.e. the source is mapped, so this is
genuinely a text-comprehension failure, not a setup gap). It fires
automatically, immediately after that failure, in the background — no
batching window, no manual button. Firing is additionally gated on the
feature being enabled and a key configured in Settings; if not configured,
behavior is unchanged from today.

## Data flow

1. `_insertRawAndParse()` in `lib/data/local_ledger.dart` runs the
   deterministic parser as it does today and stores the raw observation.
2. If the result is `unsupported`/`ambiguous` with a mapped account, and the
   AI fallback is enabled, schedule an async follow-up (fire-and-forget from
   the synchronous ingestion path, since the HTTP call cannot block the
   SQLite/Dart critical section the way the notification-freeze bugs earlier
   in this project did).
3. The follow-up sends the notification's combined text (title + body, same
   text the deterministic parser reads) to the configured endpoint with a
   prompt constrained to return strict JSON: `{amount, currency, direction,
   counterparty, confident: bool}`.
4. On a confident, well-formed response: insert an `event_candidates` row
   tagged with a distinct `parser_id` (e.g. `ai.fallback.v1`) so it's
   traceable as AI-derived versus deterministic evidence — the existing
   `event_candidates`/`financial_evidence` schema already carries
   `parser_id`, `parser_version`, and `confidence` per row, so this needs no
   schema change. Re-run `_reconcile()` as already happens after any new
   candidate.
5. The resulting transaction must not look identical to a deterministic
   auto-confirmed one — it needs to surface in the existing Review flow
   (`SpendWiseController.reviews`, which already lists transactions where
   `needsReview` is true) tagged distinctly (a new `ReviewReason`, e.g.
   `aiRead`) so the user gets a one-tap confirm before it's treated as
   settled. The exact mechanism (reusing the existing low-confidence
   review-gating path in `Reconciler`, vs. adding an explicit field) is an
   implementation decision for the planning phase, not fixed here — but the
   requirement is fixed: **an AI-derived candidate must never silently become
   a fully-confirmed transaction without the user seeing it once.**
6. On failure (malformed response, `confident: false`, network error, or a
   ~10s timeout): no candidate is inserted. The observation stays exactly as
   it is today — `parse_status = 'review'`/`'error'`, contributing to the
   existing "N observations need setup" bucket. One attempt only; no retry
   loop, no backoff, no queue.

## Provider integration

- BYOK, any OpenAI-compatible chat-completions endpoint: base URL, API key,
  model name, all entered once in Settings.
- Key stored the same way the SQLCipher database key already is — via
  `flutter_secure_storage`, never written to logs (the diagnostic logging
  added elsewhere in this project explicitly logs package names and outcomes
  only, never notification content or secrets — this feature must hold the
  same line).
- A "test connection" action in Settings so the user can verify their
  endpoint/key/model before relying on it.

## Privacy and permission policy — the part that changes this app's identity

Every top-level doc in this repo currently states, as a hard invariant, that
SpendWise has no network dependency: `README.md` lists "no ... AI
integration" and "no `INTERNET` permission" under both current limitations
and the privacy model; `PROJECT_STATUS.md` says "There is no backend,
authentication, analytics, telemetry, advertising, remote crash reporting, or
implicit network use. The Android manifest must not request `INTERNET`" and
explicitly "BYOK AI remains out of the shipped core."

Shipping this feature reverses that: `AndroidManifest.xml` must add
`<uses-permission android:name="android.permission.INTERNET" />`.
**Permissions are static in the manifest — this is present in every build
once shipped, regardless of whether any individual user ever configures a
key.** That fact must be visible to the user, not buried:

- The feature is **off by default**. No network call happens unless the user
  has both enabled it and entered a key.
- The **first time** the user enables it in Settings, show a one-time,
  explicit consent screen: notification text (not redacted — redaction risks
  stripping the exact detail the model needs, e.g. an amount or account
  suffix) will be sent to whatever endpoint they configured, and this is a
  third party outside SpendWise's local-only trust boundary.
- `README.md`, `PROJECT_STATUS.md`, and `docs/PRIVACY.md`/`SECURITY.md` all
  need updating to describe this as an optional, off-by-default,
  user-controlled exception, not a silent contradiction of the "no network"
  claim that sits three paragraphs away.

## Failure handling

Single attempt per notification. ~10 second timeout. No retries, no queue,
no rate limiting (expected volume is a handful of financial notifications a
day; this is not worth engineering around at this scale). Any failure mode —
timeout, malformed JSON, low-confidence response, HTTP error, no network —
produces exactly today's behavior: the observation sits in the existing
"needs setup" bucket. The user is never worse off for having the feature
enabled; at worst it's a no-op.

## Testing strategy

- Domain-level: a fake/mock HTTP client so the request/response contract
  (prompt construction, strict JSON parsing, confidence gating, timeout
  handling) is unit-testable without a real network call, following this
  project's existing pattern of mocking the platform channel in
  `notification_bridge_test.dart`.
- Ledger-level: verify an AI-derived `event_candidates` row reconciles into a
  transaction that is *not* immediately indistinguishable from a
  deterministic one — i.e. it must appear in `reviews` until confirmed.
- Verify the non-goal boundary: a notification from an unmapped source never
  triggers an AI call (assert on a call counter/spy), even if AI fallback is
  enabled.
- Verify failure paths (timeout, malformed response, disabled feature, no
  key configured) all leave `raw_observations.parse_status` unchanged from
  today's behavior.

## Open questions for the implementation plan

- Exact mechanism for review-gating AI-derived transactions (reuse
  low-confidence path vs. new explicit field) — needs a look at
  `Reconciler`'s current confidence-to-review-gating logic before deciding.
- Exact prompt/schema for the structured extraction request.
- Where "test connection" and the consent screen live in the Settings
  navigation.
