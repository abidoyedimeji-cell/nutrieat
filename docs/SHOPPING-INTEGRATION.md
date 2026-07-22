# NutriEat — Shopping Integration (ingredient → supermarket)

The goal: take a recipe's ingredient list and get the user from **"here's what you need"**
to **"it's in a basket at a shop I use"** with as little friction as legally and
technically possible.

The honest headline: **one-click, multi-supermarket, cross-basket checkout is not
buildable now** — not without retailer partnerships and API access you don't have. But a
genuinely useful version *is* buildable cheaply, and the data model in `ARCHITECTURE.md`
(`ingredients` + `shopping_links`) is designed so you never have to rewrite to climb the
ladder.

---

## The three levels, and where the wall is

### Level 1 — Compare & outbound links  ✅ buildable now, safe

For each recipe: show the ingredient list, and per ingredient a row of retailers with a
**"View / Shop"** button that deep-links to that retailer's search or product page. The
user lands on the supermarket site (already logged in if they have an account) and adds
to their own basket there.

You are **not** controlling anyone's basket. You're a routing layer. This is the MVP.

```
Chicken rice meal prep — Shop the ingredients

Ingredient        Tesco     Sainsbury's   Ocado     Iceland    Waitrose
Chicken breast    [ Shop ]  [ Shop ]      [ Shop ]  [ Shop ]   [ Shop ]
Basmati rice      [ Shop ]  [ Shop ]      [ Shop ]  [ Shop ]   [ Shop ]
Bell peppers      [ Shop ]  [ Shop ]      [ Shop ]  [ Shop ]   [ Shop ]
...
                                                    [ Shop all at Tesco ]
```

**Monetization:** these links go through **affiliate networks** — most major UK grocers
(Tesco, Sainsbury's, Waitrose, Ocado, Iceland, and via aggregators Asda/Morrisons) run
affiliate programmes through **Awin** and **Sovrn/Skimlinks**. You get a legitimate
tracked deep-link *and* commission, with zero scraping and zero API access. This is the
key insight the first draft missed: affiliate links are how Level 1 pays for itself.

### Level 2 — Smart matching & comparison  🟡 buildable, needs product data

Store ingredients canonically (`ingredients` table) with quantity, category, swap options
and tags (high-protein / halal / budget / vegan). Match each to concrete retailer products
so users can compare by **price, pack size, price-per-kg, fresh vs frozen, own-brand vs
premium**.

The gating resource is **product data** (names, prices, pack sizes). Options, roughly in
order of cost/robustness:

- Manual curation for the cookbook's ~50–150 ingredients (totally fine to start).
- A third-party grocery **data provider** (paid) for prices/availability.
- Scraping — fragile, ToS-risky, and prices go stale fast. Avoid as a foundation.

Prices are cached in `shopping_links.est_price_pence` and refreshed on a schedule, clearly
labelled "estimated — confirm at checkout."

### Level 3 — Add-to-basket / cross-checkout  🔴 needs partnerships; don't build early

Real "add all to basket" or "one-click checkout across Tesco + Iceland + Waitrose" runs
into a wall of retailer-specific reality:

- Separate accounts, logins and auth flows per retailer.
- Separate delivery slots, minimum basket values, and payment flows.
- Substitutions, regional stock, loyalty pricing, live price changes.
- Most UK grocery APIs (Tesco, Aldi, Lidl, M&S) are **not publicly available** — access
  requires a commercial/retailer relationship.

A few retailers accept URL parameters that pre-fill a basket, but it's undocumented,
fragile, and breaks without warning. Treat it as an experiment, never the foundation.
**Multi-supermarket single-checkout is the hardest version and should stay out of scope
until there's a real partnership or a grocery-integration provider doing the heavy lifting.**

---

## Which supermarkets, and in what order

Prioritise retailers with genuine full online-basket grocery + an affiliate route:

**Tier 1 (start here):** Tesco · Sainsbury's · Asda · Morrisons · Iceland · Ocado ·
Waitrose · Amazon Fresh.

**Tier 2 (limited online grocery behaviour):** M&S Food · Co-op · Aldi · Lidl. Aldi, Lidl
and M&S have thin online-grocery-basket coverage compared with the Tier 1 set — support
them last, if at all.

---

## Recommended MVP framing

Ship it as a **"Cookbook Shopping Assistant,"** not "checkout everything in one click."
What it does:

- Per-recipe shopping lists with ingredient swap options.
- Supermarket comparison (price / pack size / price-per-serving where data exists).
- Budget vs premium, fresh vs frozen toggles.
- "Shop at Tesco / Iceland / Ocado…" outbound affiliate links.
- Save / export a shopping list (copy, WhatsApp, notes).

This delivers real value with no deep integration, and it's the natural on-ramp: as you
add product data you light up Level 2 on the *same* tables, and if a partnership ever
appears, Level 3 slots in behind the same UI.

### Ideal user journey (MVP)

```
Open recipe → "Shop this recipe" → ingredient list
  → pick preferred supermarket (or compare all)
  → see matched products / links
  → "Shop at <retailer>" → retailer opens with product/search deep-links
  → user checks out on the retailer, in their own account
```

---

## Effort ladder (what's realistic when)

| Difficulty | Feature                                                                 |
| ---------- | ----------------------------------------------------------------------- |
| **Easy**   | Ingredient DB · recipe ingredient lists · swap options · manual/affiliate links · price-per-serving estimates · shop-by-supermarket |
| **Medium** | Live product search · price comparison · availability checks · matching logic · scheduled price refresh |
| **Hard**   | Add-all-to-basket · retailer login · saved grocery accounts · in-app checkout · multi-supermarket checkout · delivery-slot selection |

---

## How the schema supports the climb

From `ARCHITECTURE.md`:

- `ingredients` — canonical, deduped, with `swap_of` (self-referential) for substitutions
  and `tags` for filtering (halal / budget / vegan / high-protein).
- `shopping_links` — one row per `(ingredient, retailer)` holding the affiliate `search_url`
  and an optional cached `est_price_pence` + `pack_size`.

Level 1 uses just `search_url`. Level 2 fills in `est_price_pence` / `pack_size` and adds
comparison UI. Level 3, if it ever happens, adds retailer-integration code behind the same
tables. **No migration rewrite required to move up a level** — that's the whole point of
defining these two tables now even though the feature ships in Phase 3.

---

## Open decisions (for later)

1. **Affiliate network** — Awin vs Sovrn/Skimlinks (or both). Determines link format and
   how commission is tracked.
2. **Product data source** for Level 2 — manual curation vs paid provider.
3. **Price freshness policy** — how often to refresh `est_price_pence`, and how prominently
   to label estimates.
4. **Legal** — affiliate disclosure copy, and each network's/retailer's terms on
   deep-linking.
