# Wave 1D — Requirements → Tests matrix (Canonical Notification Service)

**SQL** = `supabase/tests/wave1d_verification.sql` (rolled-back; final select returns only failing rows →
empty = pass; the seq numbers below are that file's `_t.seq`). **JS** = Vitest
(`test/notifications-templates.test.ts`, `test/notifications-dispatcher.test.ts`). **Build/Deploy** =
`tsc --noEmit`, `next build`, migration history, Vercel state. Migrations: `0023` schema, `0024`
enqueue+templates, `0025`–`0028` dispatcher/feedback (+hotfixes). 0017–0022 unchanged.

| # | Required test | Verified by |
|---|---|---|
| 1 | Existing outbox rows survive | SQL `legacy_rows_preserved` (1) |
| 2 | Ambiguous legacy rows not sent | SQL `legacy_all_quarantined` (2); dispatcher claims only event-linked `queued` rows |
| 3 | Canonical event creation succeeds | SQL `enqueue_event_created` (20) |
| 4 | Duplicate event retry → one event | SQL `retry_one_event` (22) |
| 5 | Same idempotency key + different payload fails | SQL `conflict_payload_fails` (24) |
| 6 | One event → email + in-app deliveries | SQL `one_event_email_and_in_app` (21) |
| 7 | Duplicate outbox delivery prevented | SQL `no_duplicate_outbox` (23), `outbox_dedupe_enforced` (8) |
| 8 | Payload validates against template | SQL `missing_required_fails` (25); JS `validatePayload` |
| 9 | Invalid payload fails atomically | SQL `missing_required_fails` (25) |
| 10 | Required recipient missing fails safely | SQL `required_no_address_fails` (26) |
| 11 | Customer preference suppresses optional marketing | SQL `marketing_email_suppressed` (27), `marketing_in_app_kept` (28) |
| 12 | Marketing preference does not suppress required | SQL `required_not_suppressed` (29) |
| 13 | Customer A cannot see B's notifications | SQL `other_user_sees_none` (111); `get_my_notifications`/inbox RLS keyed to `auth.uid()` |
| 14 | Merchant A cannot see B's notifications | SQL `merchant_cross_invite_forbidden` (32); events scoped by `recipient_merchant_id`, inbox per user |
| 15 | Driver cannot see another driver's notification | `get_my_notifications` own-user-only (drivers are users); same self-scope as (13) |
| 16 | Anonymous sees nothing | SQL `anon_select_events_denied` (14); read RPCs revoked from anon |
| 17 | Direct browser insert/update/delete fails | SQL `auth_insert_events_denied` (11), `auth_insert_outbox_denied` (12), `auth_truncate_outbox_denied` (13) |
| 18 | Internal enqueue not browser-executable | SQL `enqueue_not_authexec` (33) |
| 19 | Dispatcher not browser-executable | SQL `claim_not_authexec` (112), `record_not_authexec` (113) |
| 20 | Actor/source cannot be spoofed | enqueue is internal-only (18); `record_audit_event` derives the actor (Wave 1B) |
| 21 | Worker claims only due rows | SQL `claim_excludes_not_due` (34) |
| 22 | Concurrent claims don't select the same delivery | SQL `no_double_claim` (35); `FOR UPDATE SKIP LOCKED` |
| 23 | Processing lease expires and recovers | SQL `abandoned_lease_reclaimed` (107) |
| 24 | Successful provider send records message id | SQL `success_message_id` (37); JS dispatcher records `resend_msg_42` |
| 25 | Provider send uses deterministic idempotency key | JS dispatcher `idempotencyKey === "ob1:email"`; `provider_idempotency_key` column |
| 26 | Temporary failure schedules retry | SQL `retryable_reschedules` (39) |
| 27 | Permanent failure does not endlessly retry | SQL `permanent_failed` (120) |
| 28 | Maximum-attempt delivery becomes dead-letter | SQL `exhausted_dead_letter` (100) |
| 29 | Manual retry is audited and idempotent | SQL `manual_retry_requeues` (121), `manual_retry_idempotent` (122), `manual_retry_audited` (123) |
| 30 | Delivery attempt history is append-only | SQL `attempt_append_only` (7) |
| 31 | Invalid webhook signature fails | JS `verifySvixSignature` tampered-body/wrong-secret → false |
| 32 | Valid webhook succeeds | JS valid signature → true; SQL `webhook_delivered` (103) |
| 33 | Duplicate webhook processed once | SQL `webhook_duplicate` (104) |
| 34 | Out-of-order webhook doesn't regress state | SQL `out_of_order_ignored` (105), `no_state_regress` (106) |
| 35 | Delivered state updates correctly | SQL `webhook_delivered` (103) |
| 36 | Delayed state updates correctly | SQL `delayed_applied` (125) |
| 37 | Failed state updates correctly | SQL `failed_applied` (127) |
| 38 | Bounce creates suppression signal | SQL `bounce_state` (108), `bounce_suppression` (109) |
| 39 | Complaint creates suppression signal | SQL `complaint_state` (128), `complaint_suppression` (129) |
| 40 | Required messages not blindly blocked by suppression | SQL `required_not_suppressed` (29) |
| 41 | Staff invitation creates event + delivery | SQL `invite_creates_event` (30), `invite_creates_email_delivery` (31) |
| 42 | Merchant invitation cross-merchant isolated | SQL `merchant_cross_invite_forbidden` (32) |
| 43 | No secret in payload/audit/attempt | SQL `payload_secret_guard` (10); audit stores summary only; attempts store no body |
| 44 | Oversized payload rejected | SQL `oversized_payload_rejected` (130) |
| 45 | Function-grant guard returns zero offenders | SQL guard (top of file) = 0 rows |
| 46 | Wave 1A tests pass | `test/identity-authz.test.ts`, `test/auth-callback.test.ts` |
| 47 | Wave 1B tests pass | `test/audit-actions.test.ts` |
| 48 | Wave 1C tests pass | `test/money.test.ts` |
| 49 | Cookbook tests pass | `test/content-engine.test.ts` |
| 50 | Typecheck passes | `npm run typecheck` |
| 51 | Production build passes | `npm run build` |
| 52 | Migration history fully aligned | preflight repair (`0021` == remote); repo↔remote 0018–0028 in order |
| 53 | Latest Vercel deployment READY | Vercel production deployment state |
| 54 | No unintended production email sent | Resend adapter is injected/mocked in tests; dispatch route secret-gated; no live send performed |

## Function-grant matrix (Wave 1D functions)

All `SECURITY DEFINER`, `search_path = public`, owner `postgres`. "Writer/internal" = revoked from
PUBLIC/anon/authenticated. "Read" = granted to authenticated but internally gated.

| Function | Kind | anon | authenticated | Intended caller |
|---|---|---|---|---|
| `enqueue_notification(...)` | writer | ✗ | ✗ | domain RPCs / trusted server |
| `claim_notification_batch(...)` | writer | ✗ | ✗ | dispatcher (service role) |
| `record_notification_result(...)` | writer | ✗ | ✗ | dispatcher |
| `deliver_in_app_notification(...)` | writer | ✗ | ✗ | dispatcher |
| `process_notification_webhook(...)` | writer | ✗ | ✗ | webhook route (service role) |
| `retry_notification_delivery(uuid)` | writer (gated) | ✗ | ✓ (admin/ops) | platform admin / operations |
| `set_notification_preference(...)` | self-write | ✗ | ✓ | customer (own prefs) |
| `get_my_notifications(...)` / `get_my_unread_count()` / `mark_notification_read(...)` / `mark_all_notifications_read()` | read (self) | ✗ | ✓ | recipient (own inbox) |
| `get_notification_operational_summary()` | read (gated) | ✗ | ✓ (ops/finance/admin) | operations/finance/admin |
| `_notification_*` (guards/backoff/helpers) | internal | ✗ | ✗ | internal only |

Internal-function guard (top of `wave1d_verification.sql`) enumerates `_notification*` plus the named
writers and asserts zero are anon/authenticated-executable.
