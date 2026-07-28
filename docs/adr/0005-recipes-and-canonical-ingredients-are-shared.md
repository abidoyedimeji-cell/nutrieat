# ADR 0005 — Recipes and canonical ingredients are shared

**Status:** Accepted · 2026-07-28

## Context
Recipes already hold ingredients, quantities, substitutions, nutrition and calories. The marketplace
needs canonical ingredients to map recipes to local products. Duplicating this data into the
marketplace would create drift and double maintenance.

## Decision
`recipes`, `ingredients`, `recipe_ingredients` and substitutions are **shared platform data**. The
Farmers Market **consumes** them (read side); it does not copy or re-define canonical ingredients.
The canonical flow is `Recipe → Ingredient → local availability → Merchant catalogue → Basket`.

## Consequences
- Canonical ingredients are the single source of truth; merchant products reference them (ADR 0006).
- "Shop this recipe locally" reads the existing ingredient graph.
- CMS ownership of recipes/ingredients stays in the content service; the marketplace never edits them.
