# NutriEat — Build Log

Engineering journal. Newest first. Each entry: what shipped, key decisions, issues.

---

## Sprint 1 — Foundation ✅
**Status:** complete · database live

**Highlights**
- Next.js 15 (App Router) + TypeScript + Tailwind scaffold; brand palette from the
  cookbook spreads. Build verified (`next build`, 15 routes).
- Public pages: landing, `/early-access`, `/survey` (Google-Form embed slot), `/about`,
  `/faq`, privacy/terms/refund drafts, `sitemap.xml`, `robots.txt`.
- Early-access form (client) captures UTMs → `POST /api/leads` → `create_cookbook_lead`.
- Data layer: enums, all core tables, deny-by-default RLS, SECURITY DEFINER RPCs
  (`create_cookbook_lead`, `submit_cookbook_survey`, `get_public_recipe`), seed
  (5 categories, 7 retailers, 37 ingredients, 3 meal plans, product + 3 GBP variants).
- Recipe tables made import-ready (`0005`): subtitle, macro_adjustments, nutrient_highlights,
  per-ingredient calories, `recipe_swaps`.

**Supabase — connected & verified** (project `nrvtnfyityafwbuhrxrt`, `supabase-back-door`)
- Applied migrations `0001`–`0006`; ran seed. Counts verified
  (5/7/37/3/1/3; variants pdf:999, physical_book:1799, bundle:2499 GBP pence).
- `create_cookbook_lead` verified: inserts, lowercases email, **dedupes on conflict**.
- Verified as the `anon` role: RPC executes and inserts (definer); direct reads of
  `cookbook_leads` / `survey_responses` / `payment_events` / `orders` are **denied**;
  public catalogue (`products`, `ingredients`) readable (RLS gates rows).

**Decisions**
- Money locked GBP (£9.99 / £17.99 / £24.99); the earlier USD figures are superseded.
- Bundle launches at day one (3 products).

**Issues / resolved**
- `next@15.1.6` flagged with a security advisory → upgraded to `15.5.x` (patched).
- Advisor `graphql_table_exposed` WARNs → added `0006_harden_grants`: revoked
  anon/authenticated grants on private tables so they leave the public API surface
  entirely (RLS already protected rows; this removes schema exposure too).
- `security_definer_function_executable` WARNs on the 3 RPCs → **by design** (public
  write via hardened definer functions; pinned `search_path`, input validation).

---

## Sprint 2 — Commerce 🚧 (next)
Product page · Stripe Checkout (PDF + hardback + bundle) · orders · webhook (signature +
idempotency) · PDF entitlements (launch-day gated) · physical fulfilment record ·
confirmation emails · real previews (3 recipes / 2 smoothies / 1 superfood).

## Sprint 3 — Content Engine (planned)
One clean structured import of 40 meals + 20 smoothies + 20 superfoods · Cookbook CMS.
