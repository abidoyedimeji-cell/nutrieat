# ADR 0006 — Merchant products optionally link to canonical ingredients

**Status:** Accepted · 2026-07-28

## Context
A merchant product like "Six large free-range eggs" maps cleanly to the canonical ingredient "Eggs".
A specialist butcher bundle may not map to any single canonical ingredient. A mandatory link would
block onboarding of legitimate products; no link would break "shop this recipe locally."

## Decision
`market_products.ingredient_id → ingredients` is a **nullable** foreign key. Where a product maps to
a canonical ingredient it is linked; where it doesn't, the link is left null. The relationship is
**optional, never mandatory**.

## Consequences
- An ingredient page can surface relevant local merchant products **without** duplicating canonical
  ingredient records.
- Import/onboarding never fails for want of an ingredient match; matching can be improved later.
- Recipe→product discovery degrades gracefully for unmatched specialist products.
