# ADR 0004 — Marketplace orders remain separate from cookbook orders

**Status:** Accepted · 2026-07-28

## Context
Cookbook orders are single-product digital/physical purchases with a simple lifecycle. Marketplace
orders fan into per-merchant sub-orders with item-level fulfilment, evidence, returns and split
settlement. Forcing both into one table would create a lifecycle mismatch and unsafe coupling.

## Decision
Cookbook orders (`orders`/`order_items`, `order_status`) and marketplace orders
(`market_orders` → `merchant_sub_orders` → `market_order_items`, `market_order_status`) stay in
**separate tables with separate lifecycles**. They **share only patterns** — integer-pence money and
the Stripe-event idempotency ledger pattern — not tables.

## Consequences
- No shared order enum; each lifecycle evolves independently.
- Shared money/payment abstractions are acceptable; shared order rows are not.
- Reporting that spans both products joins at the customer/ledger level, not the order table.
