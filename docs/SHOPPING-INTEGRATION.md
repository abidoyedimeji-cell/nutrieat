# NutriEat — Grocery & Ingredient Shopping

The grocery feature is a **later phase**, but the cookbook's data is structured correctly
**from the start** so it can support grocery features without a rewrite. This doc covers
the guiding principle, the six levels, retailers, and how the schema underpins the climb.

The honest headline: **one-click multi-supermarket checkout is not buildable now** —
levels 5 and 6 need retailer partnerships/APIs you don't have. But levels 1–3 are cheap
and genuinely useful, and they run on the same tables.

---

## Core principle: structured ingredients from day one

A recipe must **not** store ingredients only as a paragraph. Every ingredient becomes a
reusable structured record:

```
Canonical ingredient : Chicken breast
Recipe quantity      : 500 g
Category             : Meat and poultry
Alternatives         : Chicken thigh, turkey breast, tofu
Dietary tags         : High-protein
Shopping search term : Fresh chicken breast fillets
```

This is why `ingredients`, `recipe_ingredients`, and `ingredient_substitutions` exist in
the core schema even though shopping ships later — the structured ingredient is the join
point to supermarket products.

---

## The six levels

### Level 1 — Shopping-list export  ✅ simplest & safest
Generate a recipe shopping list, combine ingredients across several recipes, copy /
download / send to WhatsApp / save to account. Pure aggregation over
`recipe_ingredients` (see the `get_shopping_list_for_recipe` / `_meal_plan` RPCs). No
retailer data required.

### Level 2 — Retailer search links  ✅ no live data
Each ingredient links to a **search page** at selected supermarkets, using its
`shopping search term`.

```
Chicken breast → Search Tesco · Search Morrisons · Search Ocado
```

Best done through **affiliate networks** (Awin, Sovrn/Skimlinks) — most major UK grocers
run affiliate programmes, giving legitimate tracked deep-links **and** commission with no
scraping and no API access. This is how Level 2 pays for itself.

### Level 3 — Manually curated product matching  🟡 needs upkeep
Store selected supermarket products for common ingredients so users compare **product
name, pack size, price, price-per-unit, fresh/frozen, budget/premium, supermarket**.
Accurate but must be maintained regularly. Prices are cached estimates, clearly labelled
"confirm at checkout."

### Level 4 — Live product & price data  🔴 needs data access
Requires retailer APIs, affiliate feeds, licensed grocery data, retailer partnerships, or
compliant data providers. A real cost/relationship step.

### Level 5 — Add to retailer basket  🔴 retailer-specific
Needs retailer-specific integration; unavailable for many supermarkets. URL-parameter
basket pre-fill exists for a few retailers but is undocumented and fragile — an
experiment, never a foundation.

### Level 6 — Multi-retailer checkout  ⛔ not recommended early
Creates complexity around multiple accounts, multiple payments, minimum basket values,
delivery fees, delivery slots, substitutions, loyalty pricing, regional stock, failed
orders, customer support, and refund allocation. **The app should help users move from
recipe → shopping list, not become a grocery marketplace.**

---

## Retailers to consider

Tesco · Sainsbury's · Asda · Morrisons · Iceland · Ocado · Waitrose · Co-op ·
Amazon Fresh · M&S Food.

**Advertise retailer support only after testing** for: online availability, product
coverage, location restrictions, delivery coverage, link reliability, basket behaviour,
and account requirements. (Aldi/Lidl/M&S have thinner online-grocery-basket coverage than
the full-basket retailers — support them last, if at all.)

---

## Future grocery schema

Introduced in Phase 7+, built on the day-one ingredient structure:

- **retailers** — name, slug, affiliate/base URL, active.
- **retailer_products** — retailer, product name, pack size, url, fresh/frozen, own-brand
  vs premium.
- **ingredient_product_matches** — `ingredient_id ↔ retailer_product_id`, match quality.
- **prices** — retailer_product, `price_cents`, `currency`, `price_per_unit`, captured_at.
- **availability** — retailer_product, in-stock, region, checked_at.
- **shopping_lists / shopping_list_items** — user-owned saved lists (RLS: owner-only).

Level 1 needs only `ingredients` + `recipe_ingredients`. Level 2 adds `retailers` +
affiliate search URLs. Level 3 adds `retailer_products` + `ingredient_product_matches` +
`prices`. Levels 4–6 add integration code behind the same tables. **No migration rewrite
to move up a level.**

---

## Sequencing (from the roadmap)

> Validate demand → build the audience → sell the cookbook → structure recipe & ingredient
> data → observe customer behaviour → add shopping-list tools → pursue retailer
> integrations.

Grocery is **Phase 7 (assistant MVP: levels 1–2)** and **Phase 8 (retail partnerships:
levels 3–5 where supported)**. See [`ROADMAP.md`](./ROADMAP.md).

## Open decisions (later)

1. Affiliate network — Awin vs Sovrn/Skimlinks (or both); determines link format + tracking.
2. Level-3 product-data source — manual curation vs paid provider.
3. Price-freshness policy and how prominently estimates are labelled.
4. Legal — affiliate disclosure copy; each network's/retailer's deep-linking terms.
