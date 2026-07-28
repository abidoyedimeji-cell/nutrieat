# ADR 0008 — All financial and fulfilment actions are auditable and idempotent

**Status:** Accepted · 2026-07-28

## Context
Payments, refunds, transfers and fulfilment transitions can be retried (webhook redelivery, network
retries, double submits). Without idempotency they double-charge or double-pay; without audit they
can't be reconciled or disputed.

## Decision
Every financial and fulfilment action is **idempotent** and **audited**. Stripe events are
deduplicated by a unique `stripe_event_id` ledger (`payment_events` / `market_payment_events`); every
money operation carries its own unique `idempotency_key` (order create keyed by `basket_id`, refunds,
transfers); every privileged state change writes an append-only `audit_events` row (actor, action,
entity, before/after summary, correlation/request id, reason). Money/ledger tables separate the
distinct concepts (customer payment, platform fee, merchant gross, commission, hold, adjustment,
refund, credit, transfer, Stripe fee, cashback, points) — **no vague single "balance."**

## Consequences
- Duplicate checkout/refund/transfer events change financial records **exactly once**.
- Any order reconciles from customer charge → merchant transfer → platform revenue.
- Audit records **privileged state changes**, not harmless page views.
- Non-cash points and cash-valued entries never collapse into one number.
