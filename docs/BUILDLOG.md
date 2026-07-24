# NutriEat — Build Log

Engineering journal. Newest first. Each entry: what shipped, key decisions, issues.

---

## Sprint 2 — Commerce ✅
**Status:** complete · build verified · DB flow verified

**Highlights**
- **`/cookbook` product page** (server, `force-dynamic`): hero, features, what's-included,
  three pricing cards (PDF / Hardback / Bundle), FAQ, CTA. Prices read from Supabase
  (service role) — never hardcoded, never from the browser.
- **`POST /api/checkout/create`**: validates the variant, reads price + currency from the
  DB, creates the **pending order**, then a Stripe Checkout Session using the env
  `STRIPE_PRICE_ID_*` (physical/bundle collect shipping + offer UK £3.99 / Intl £8.99
  options; PDF shows a launch-day note). Stores `stripe_checkout_session_id` on the order.
- **`POST /api/stripe/webhook`**: raw-body signature verification; idempotent via
  `payment_events` (pre-check + unique backstop; event recorded only after success so a
  failed run safely retries). Handles `checkout.session.completed` /
  `async_payment_succeeded` (fulfil), `async_payment_failed` / `payment_intent.payment_failed`
  (→ `payment_failed`), `checkout.session.expired` (→ `cancelled`), `charge.refunded`
  (→ `refunded` / `partially_refunded`). Validates currency + amount against the DB.
  Fulfilment is idempotent (guarded order/items/entitlement).
- **PDF entitlement**: created on payment, **locked until launch day** (`available_at` =
  product `launch_date`, currently null = locked), **no signed URL** yet.
- **Physical fulfilment**: shipping address/country/zone captured from the session,
  `fulfilment_status` → `pending`, `tracking_number` left null for the distributor step.
- **Confirmation email** via Resend (order summary, edition, amount, launch-day reminder,
  support address) — non-fatal so a mail failure never fails the webhook. Sender is
  **env-driven only** (`EMAIL_FROM` / `SUPPORT_EMAIL`, verified domain `oladimejisultan.org`)
  — no hard-coded domain; **throws clearly in production if `EMAIL_FROM` is unset**;
  `SUPPORT_EMAIL` falls back to the sender address. A shared `sendEmail()` gives the same
  verified sender to pre-order/payment, refund, and the future PDF-release emails.
- **`/checkout/success`** (cosmetic — webhook is authoritative) and **`/checkout/cancelled`**.

**Verification**
- `next build` passes; types clean; 18 routes.
- DB flow simulated against the live project (rolled back, nothing persisted):
  PDF order pending→**paid**, order_item created, entitlement **active + locked**, duplicate
  webhook event **deduped to 1** (idempotency), hardback fulfilment **pending**, total
  £17.99+£3.99 = **£21.98**, GB → zone **uk**. Commerce tables confirmed empty afterward.
- Live card-payment paths (PDF/hardback/bundle purchase, failed, cancelled, refund) require
  the deployed environment — drive with Stripe test events / `stripe trigger` against the
  deployed `/api/stripe/webhook` (see STATUS verification notes).

**Decisions**
- No schema changes needed — Sprint 1 tables already covered orders/items/events/
  entitlements/shipping. (Constraint honoured: additive-only, none required.)
- `available_at` null/future = locked, past = available (redeem RPC lands with digital
  delivery, post-launch).

**Issues / resolved**
- Added deps `stripe@17`, `resend@4`.

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

## Sprint 3 — Content Engine (planned)
One clean structured import of 40 meals + 20 smoothies + 20 superfoods · Cookbook CMS.
