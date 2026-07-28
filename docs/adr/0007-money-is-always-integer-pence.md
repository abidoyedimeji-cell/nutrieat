# ADR 0007 — Money is always stored as integer pence

**Status:** Accepted · 2026-07-28

## Context
Floating-point money causes rounding errors that are unacceptable in commission, refund and payout
maths. The cookbook already stores integer minor units (`*_cents`) + explicit `currency='GBP'`.

## Decision
**All money is an integer number of pence (GBP)**, in `*_cents` columns with `CHECK (>= 0)` (signed
only for ledger/adjustment deltas), across every product and service. No floats for money, anywhere.
Commission rates are `numeric(4,3)`; commission is `round(gross * rate)` computed once, never
re-rounded per item. Cash-valued amounts (pence) and non-cash points are **never summed** (ADR 0008).

## Consequences
- One representation platform-wide; reconciliation is exact.
- Currency is GBP-locked for now; a future multi-currency need adds a currency column, not a redesign.
- Reward ledger separates `kind=cashback` (pence) from `kind=points` (whole points).
