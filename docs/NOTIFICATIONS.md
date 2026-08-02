# NutriEat Platform — Notification Service (Wave 1D)

One reusable pipeline for every product: **business event → delivery outbox → provider adapter →
delivery-status feedback**. Two separate concepts:

- **`notification_events`** — the canonical, immutable record of what the platform *decided to
  communicate* (business intent). One row per business intent.
- **`notification_outbox`** — the channel-specific *delivery queue* (one row per event × recipient ×
  channel × template version). Records delivery work and delivery state.

`notification_events → one or more notification_outbox rows → one or more notification_delivery_attempts`.
Business events, delivery jobs, and delivery attempts are **never** collapsed into one table.

## Delivery semantics (no universal exactly-once claim)
- Exactly-once **event creation** by idempotency key.
- Exactly-once **outbox creation** per event/recipient/channel/template version.
- Safe **at-least-once** worker processing.
- Provider idempotency where available (Resend) — an *additional* defence, not the source of truth.
- Webhook deduplication by provider event id.
- No duplicate *visible* notification during ordinary retries.
- **The database remains the long-term source of deduplication.**

## Migration-history alignment (preflight)
The repository is applied to Supabase via the MCP `apply_migration` (which stamps 14-digit timestamp
versions), not `supabase db push`; there is no `supabase/config.toml` and the Supabase CLI is not
available in the build environment. The one Wave 1C.1 discrepancy — repo `0021_fix_merchant_summary_null_coalesce`
vs remote history name `0020a_fix_merchant_summary_null_coalesce` — was repaired by renaming the remote
`schema_migrations` record to `0021…` (metadata only; **no schema SQL was rerun**, schema unchanged).
The two bodies are byte-identical after stripping comments (md5 `1a4600cb28ae6b29ff6b4b440eb0ffb5`) and
the live `get_merchant_finance_summary` is the corrected coalesce-each-sum version.

**Before:** remote `0020a_fix_merchant_summary_null_coalesce` (version `20260728231728`).
**After:** remote `0021_fix_merchant_summary_null_coalesce` (same version) — matches the repo file.
Repo ↔ remote now map one-to-one in order for 0018–0022. (Pre-existing cosmetic: remote names for
0010–0017 omit the numeric prefix — from earlier MCP-applied waves; non-blocking, schema identical.)

## Current-vs-required gap report (preflight audit)

| Concern | Current | Required (Wave 1D) | Action |
|---|---|---|---|
| Canonical event history | absent (`notification_events` does not exist) | immutable business-intent record | **create** additively |
| Delivery queue | `notification_outbox` minimal: `id,type,recipient_email,recipient_user_id,payload,status,created_at` | + event FK, channel, provider, typed delivery status, attempts, lease/lock, provider ids, timestamps, safe error | **extend** additively (no drop/rename) |
| Delivery attempts | absent | append-only attempt history | **create** |
| Preferences | absent | per user/category/channel with required-vs-optional | **create** |
| Suppression | absent | bounce/complaint → suppress optional email only | **create** |
| Enums | none (status/type are `text`) | category/channel/delivery-status/audience/priority/attempt-result/suppression-reason | **create** |
| Enqueue service | `_enqueue_notification(text,text,uuid,jsonb)` — bare insert, no event/channel/idempotency/preferences/audit | one canonical `enqueue_notification` | **supersede** (repoint invite callers; keep stub) |
| Dispatcher | none | provider-neutral worker (lease, retry/backoff, dead-letter) | **create** (route + secret + Vercel cron) |
| Provider adapter | `lib/email.ts` — direct Resend, 4 inline-HTML templates | one Resend adapter (idempotency key, classified errors, message-id) | **create**; keep `lib/email.ts` for cookbook (migration plan) |
| Provider feedback | none | signed Resend webhook, dedupe, out-of-order-safe, suppression | **create** route + dedupe table |
| In-app channel | none | inbox projection + own-only read ops | **create** |
| Templates | inline HTML in `lib/email.ts` | versioned, code-owned registry w/ payload schema + fixtures | **create** registry |
| Scheduling | **none** (no `vercel.json`/`vercel.ts`, no cron route) | Vercel Cron → protected dispatch route | **create** |
| Env | `RESEND_API_KEY, EMAIL_FROM, SUPPORT_EMAIL` | + `RESEND_WEBHOOK_SECRET`, `NOTIFICATION_DISPATCH_SECRET` | **add** to `.env.example` |
| Grants/RLS | outbox RLS on (`is_platform_staff()` read); `authenticated` has stray `TRUNCATE/REFERENCES/TRIGGER` | deny-by-default; scoped read RPCs; stray grants revoked | **harden** |
| Audit | canonical `record_audit_event` | `notification_*` audit actions | **integrate** |

## Legacy `notification_outbox` classification
- **Total rows:** 2.
- **Event types:** `platform_staff_granted` (1), `platform_staff_invited` (1) — from the Wave 1A super-admin bootstrap.
- **Recipient patterns:** both have `recipient_email`; `granted` also has `recipient_user_id`, `invited` does not.
- **Sent/unsent:** both `status='pending'` — **never sent** (no dispatcher has ever existed).
- **Duplicates:** none. **Payload secrets:** none (`{role: …}` only).
- **Ambiguous:** both lack channel/template/idempotency and cannot be deterministically linked to a canonical event (none existed).
- **Decision:** **preserved**, backfilled to `delivery_status='quarantined'` with `notification_event_id` NULL, so the dispatcher (which claims only `delivery_status='queued'` rows with a non-null event) can **never** send them. No silent deletion, no silent send, no forced backfill.

## Authoritative structures for all NEW notifications
`notification_events` (intent) + `notification_outbox` (delivery) + `notification_delivery_attempts`
(history) + `notification_inbox` (in-app) + `notification_preferences` + `notification_suppressions`
+ `notification_provider_events` (webhook dedupe). The legacy bare `_enqueue_notification` insert path
is superseded by the canonical `enqueue_notification` service and is retained only as a thin compatibility
shim.

*(Compliance note: final unsubscribe/suppression policy wording requires legal/privacy review; this wave
implements the mechanism, not the legal policy.)*
