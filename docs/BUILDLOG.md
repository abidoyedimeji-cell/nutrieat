# NutriEat — Build Log

Engineering journal. Newest first. Each entry: what shipped, key decisions, issues.

---

## Content Engine + CMS ✅
**Status:** complete · typecheck + tests + build pass · DB verified

**Admin auth (temporary env allowlist)**
- `ADMIN_EMAILS` (comma-separated), read **server-side only**; pure logic in
  `lib/admin-allowlist.ts` (normalise/trim/lowercase, empty ⇒ deny all). `requireAdminPage()`
  guards every `/admin` page; `assertAdmin()` guards every server action. Admin writes use
  the service-role client **after** the allowlist check. Unit-tested (5 tests).

**Migration 0008 (additive)** — recipes: `import_status`, `admin_note`, `source_title`,
`source_filename`, `updated_at`; ingredients: `aliases`, `image_url`; public `recipe-images`
bucket. No drops/renames. `macro_adjustments`/`nutrient_highlights` stay JSONB (approved).

**CMS** (`/admin`): dashboard; recipes list + create + full editor (all fields, macros,
JSONB macro-adjustments/nutrient-highlights, visibility, import_status, admin note,
per-ingredient add/remove with calories, recipe-specific swaps, image upload, publish/
archive **with validation**, preview link); ingredients list/create/edit (aliases, tags,
image, global substitutions); meal-plans list/edit (recipe assignment). Server actions,
`revalidatePath`. Publish is blocked for `incomplete` recipes (enforces the no-incomplete
rule in the CMS too).

**Import** (`supabase/import/content_import.sql`, idempotent, honest — nothing invented):
- **20 superfoods** → complete, category superfoods.
- **20 smoothies** → ingredient lists only (144 links) → `incomplete` drafts + admin_note.
- **12 meals** → title/source only (1, *The Ultimate Steak…*, carries captured macros +
  nutrients + 4 swaps) → all `incomplete` drafts.
- Report: 52 recipes (20 complete / 32 incomplete), 81 ingredients. **Idempotent verified**
  — re-run produced identical counts (distinct_slugs = 52, no duplicates).

**Public previews**: `/recipes` + `/recipes/[slug]` (RLS-bound anon reads), preview section
on `/cookbook`, dynamic sitemap. Published 3 complete superfoods as `public_preview`.
**Data rules honoured**: only complete records published; smoothies/meals held as drafts.

**Verification**
- typecheck clean; **5/5 tests pass**; `next build` passes (34 routes + middleware).
- **RLS isolation** (as `anon`): sees only the 3 published previews; **0** paid recipes,
  drafts, recipe_ingredients or swaps. Paid content is unreachable publicly (queries,
  sitemap, metadata).
- Admin allowlist unit-tested (authorised/unauthorised/empty/null). Live click-through of
  the admin UI needs a signed-in allowlisted session (magic-link redirect allowlist pending).

---

## Accounts + Digital Delivery ✅
**Status:** complete · build verified · RPCs verified

**Highlights**
- **Supabase Auth (passwordless magic link)** via `@supabase/ssr`: browser + cookie-bound
  server clients, session-refresh `middleware.ts`, `/login`, `/auth/callback`,
  `/auth/signout`.
- **Protected `/account` area**: overview, `/account/orders` (status, edition, total,
  fulfilment/tracking), `/account/downloads`. Layout guards auth (redirect to `/login`).
- **`claim_my_purchases()` RPC**: on account load, attaches guest orders + entitlements to
  the logged-in user by **case-insensitive email match** (bridges guest checkout → account).
- **`redeem_download()` RPC + `/api/downloads/[id]`**: validates ownership, the **launch-day
  gate** (`available_at`), and the download limit; increments the count; the route mints a
  **15-min signed URL** from the private `cookbook-pdf` bucket (service-role only).
- PDF stays **locked until launch day**; the downloads page shows "Unlocks on launch day".

**Verification** (live DB, rolled back)
- redeem: locked entitlement **refused** (`not_yet_available`); after unlock returns the
  path and **increments count to 1** (limit then enforced).
- claim: guest order + entitlement with mixed-case email attached to the authenticated
  account (`claimed_orders=1`, `claimed_entitlements=1`).
- `cookbook-pdf` private bucket created. Build passes (24 routes + middleware); types clean.

**Open config / follow-ups**
- **Supabase Auth redirect allowlist**: add the site URL + `…/auth/callback` under
  Auth → URL Configuration, or magic links won't complete. (Flagged to user.)
- Magic-link emails send via Supabase's built-in email until custom SMTP (e.g. Resend) is
  configured — fine for testing, configure for volume.
- The actual **PDF file** isn't uploaded to the bucket yet (nothing to deliver pre-launch);
  upload on launch day, set `products.launch_date`, and backfill entitlement `available_at`.

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

## Follow-ups (post-Sprint-2)
- **Live production verification:** early-access signup tested on the deployed site
  (`nutrieat-sigma.vercel.app`) — lead landed in `cookbook_leads` with correct email
  (lowercased), name, source, preferred_format, landing_page and referrer. Full path
  deployed app → `/api/leads` → RPC → DB confirmed working.
- **Welcome email (Email 1) built:** `sendWelcomeEmail` via the verified Resend sender;
  `/api/leads` sends it **once, to new signups only** (service-role existence check
  distinguishes new vs returning), non-fatal. Closes the gap where the success UI promised
  a welcome email that wasn't yet sent.

---

## Sprint 3 — Content Engine (planned)
One clean structured import of 40 meals + 20 smoothies + 20 superfoods · Cookbook CMS.
