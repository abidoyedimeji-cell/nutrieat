# NutriEat Platform — Audit Convention (Wave 1B)

The canonical, append-only audit service. One table (`audit_events`), one writer
(`record_audit_event`), used by every product and service (cookbook, Farmers Market, platform
admin, future products). Governed by ADR 0008 (all financial/fulfilment actions auditable +
idempotent) and ADR 0009 (deny-by-default, server-side only).

## What must be audited
Every **privileged state transition** — role/staff changes, merchant/driver operations, orders,
item fulfilment, refunds, settlements, rewards/referrals, support decisions, financial adjustments.
**Not** harmless page views or UI events.

Each event answers: **who** acted (`actor_user_id`/`actor_type`), **in which role** (`actor_role`,
`actor_merchant_id`), **through which product/service** (`product_context`, `source_application`),
**what changed** (`action`, `entity_type`/`entity_id`, `before_summary`/`after_summary`),
**why** (`reason_code`/`reason_text`), **which workflow** (`request_id`/`correlation_id`/
`operation_id`/`idempotency_key`), and **when** (`created_at`).

## Action naming
Stable, domain-oriented `namespace.action` (lowercase, `snake_case` segments). The writer **rejects**
anything that isn't `^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$`, and explicitly rejects UI-oriented names.

| ✅ Use | ❌ Never |
|--------|---------|
| `platform_staff.invited`, `platform_staff.role_changed`, `platform_staff.suspended` | `button_clicked` |
| `merchant_staff.invited`, `merchant_staff.revoked` | `admin_page_saved` |
| `driver.created`, `driver.activated`, `driver.suspended` | `modal_confirmed` |
| `merchant.created`, `order.created`, `item.picked` | `page_view` |
| `refund.approved`, `settlement.adjusted` | `form_submitted` |

Namespaces track the entity/domain, not the screen. New actions are added freely as long as they
follow the pattern; there is **no enum** for `action` (it would churn constantly).

## Actor model (`audit_actor_type`)
`authenticated_user · platform_staff · merchant_staff · driver · customer · service ·
stripe_webhook · scheduled_job · system_migration`.

- **Human actions** store the real `auth.users.id`; the writer derives `actor_type` + `actor_role`
  from `platform_staff`/`merchant_staff`/`drivers` when not supplied.
- **Non-human actors** (webhooks, jobs, migrations) pass an explicit non-human `actor_type` and a
  source; **the writer never fabricates a user id** for them (a human `actor_type` with no
  `actor_user_id` is rejected).

## Product & source
`product_context`: `platform · cookbook · farmers_market` (extend additively for future products).
`source_application`: `web · admin · merchant_portal · driver · webhook · scheduled_job ·
database_rpc`.

## Immutability (defence in depth)
1. **Trigger** blocks `UPDATE`/`DELETE`/`TRUNCATE` for **every** role, including `service_role`
   (RLS alone is insufficient — privileged connections bypass it).
2. **Grants** revoked: no `INSERT`/`UPDATE`/`DELETE`/`TRUNCATE` for anon/authenticated; anon has no
   grant at all; `SELECT` is RLS-gated to platform staff.
3. **Writes only** through the SECURITY DEFINER `record_audit_event` (or its `_record_audit` shim) —
   no direct table writes.
4. **Corrections never mutate** the original: append a new event with `supersedes_event_id`
   pointing at the earlier event.

## Idempotency & transactions
- Pass an `idempotency_key` for retry-safe operations; a repeat returns the **existing** event id
  (exactly-once).
- The audit insert runs in the **same transaction** as the business change it records — if the
  business transition rolls back, so does its audit event, and vice-versa. A privileged change
  **cannot commit without** its audit record.

## Payload hygiene
- `before_summary`/`after_summary`/`metadata` are **concise JSONB summaries**, not full-row dumps
  (combined limit 16 KB — the writer rejects larger).
- The writer rejects payloads whose keys look secret-bearing (`password`, `token`, `secret`,
  `api_key`, `card_number`, `cvv`, `ssn`, `private_key`, …). **Never** log secrets, tokens, card
  data, or unnecessary personal data.

## The notification stubs (unchanged reminder)
`notification_outbox` remains the Wave-1D transport/delivery-queue stub; the canonical
`notification_events` history is added in Wave 1D — separate from audit. Audit ≠ notifications.

## Using the writer (server-side only)
`record_audit_event(p_action, p_entity_type, p_entity_id, …)` — see `0015_audit_writer.sql` for the
full parameter list. Existing identity RPCs call it via `_record_audit(action, entity_type,
entity_id, summary)`; new domains should call `record_audit_event` directly with the richer context
(product, source, reason, before/after, correlation ids). Do **not** create competing audit
functions — extend this one.
