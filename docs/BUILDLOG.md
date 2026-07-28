# NutriEat — Build Log

Engineering journal. Newest first. Each entry: what shipped, key decisions, issues.

---

## Platform Wave 1C — Money & Ledger Foundation ✅
**Status:** migration `0017` applied to live Supabase · all gates passed · typecheck + tests + build pass

Reusable, append-only, idempotent **double-entry** financial ledger for **cash-valued** movements
only (integer pence, GBP). **Points stay in `reward_ledger`** — never posted to the cash ledger,
summed with cash, or implicitly converted. Sits **alongside** the order tables (does not turn them
into accounting tables). Money model: `docs/MONEY-MODEL.md`.

**Preflight (mandatory Wave-1B checks):** integration deployment READY; **root-caused the
default-privilege issue** — Supabase `ALTER DEFAULT PRIVILEGES` (for `postgres` + `supabase_admin`)
grants EXECUTE on every new `public` function to PUBLIC/anon/authenticated/service_role, so
`revoke from public` is insufficient. Chose **explicit revokes + an automated guard** over altering
Supabase defaults. 0011–0016 aligned repo↔ledger; branch clean.

**PR A — ledger (`0017`):** `financial_accounts` (owner_type/kind/currency/product_scope, unique
natural identity; platform singletons seeded, per-owner on demand via
`_get_or_create_financial_account`), `financial_journals` (immutable header: product_context,
operation_type, source entity, correlation/operation/request ids, idempotency_key, reversal + audit
links), `financial_postings` (immutable lines, positive pence, debit/credit). **Balance guaranteed
twice** — the posting RPC + a **deferred constraint trigger** (`debits=credits`, ≥2 lines).
Append-only via update/delete/truncate triggers. `post_financial_journal()` is the **only write
path** — SECURITY DEFINER, internal-only, idempotent, audits (finance category) in the same txn.
Reconciliation: `get_financial_account_balances()`, `get_ledger_totals()` (finance/admin-gated).
RLS deny-by-default; finance/admin read only.

**PR B — docs + tests:** `docs/MONEY-MODEL.md`, `lib/money.ts` (pure double-entry balance +
value-system separation) + tests, doc updates.

**Gates (verified live):** **£100 order reconciled exactly** (charge 10000 = merchant 8000 +
platform fee 2000; net 1800 residual after £2 Stripe fee; merchant_payable nets to 0); unbalanced
journal **rejected**; UPDATE/DELETE/TRUNCATE **blocked**; **idempotent** (same key → one journal);
writer **not** anon/authenticated-executable; ledger tables no anon read / no authenticated write;
automated internal-function guard returns empty.

---

## Platform Wave 1B.1 — Audit Service Closeout ✅
**Status:** migration `0016` applied to live Supabase · all gates passed · typecheck + tests + build pass

Completes the parts of the Wave-1B brief omitted when it arrived truncated. Preserves `0014`/`0015`.

**🔴 Security fix (preflight finding):** `record_audit_event` / `_record_audit` / `_audit_has_secret`
were **executable by anon + authenticated** — Supabase's default privileges auto-grant EXECUTE on
function creation, and the 0015 `revoke … from public` didn't remove the direct role grants. The
canonical writer was therefore **browser-callable = actor-spoofing hole**. `0016` revokes execute
from anon + authenticated (+ public) on all internal audit functions. Verified: writer/shim/helpers
`false/false`; identity RPCs + `get_audit_events` stay `authenticated`-only (gated internally).

**Restricted read (`get_audit_events`):** one SECURITY DEFINER, pinned-search_path, `authenticated`-
only read RPC — bounded pagination (max page 100), safe projection (no `metadata`/`ip`/`user_agent`),
per-role category scope, cross-merchant isolation. super/platform_admin = all; operations = ops only;
finance = finance only; support = support only; merchant_admin = own-merchant `merchant` events only;
managers/pickers/drivers/customers/anon **denied**. Proven on live DB (ops sees 0 security/finance;
finance sees 0 security; merchant A sees 0 of B; customer/driver forbidden).

**Classification:** one minimal additive field `event_category` (enum) stamped at **write time** by
action namespace (`_audit_category_for`) — read scoping filters the stored enum, never action strings.
Legacy null-category rows stay visible only to platform admins.

**Wave 1A enrichment:** the 9 identity RPCs re-emit canonical events with **before/after summaries +
`reason_code` + merchant scope**, and an explicit **`system_migration`** actor for bootstrap. Same
signatures, same authorisation rules. Proven: role change records
`operations_staff->finance_staff reason=role_change`.

**PR B:** `docs/AUDIT-REQUIREMENTS-MATRIX.md` (all 32 requirements → tests), `docs/AUDIT-RETENTION.md`
(categories, retention considerations pending legal/accounting sign-off, account-deletion/
pseudonymisation, prohibited fields, safe summaries), `lib/audit-actions.ts` `auditCategoryFor` mirror
+ tests, `supabase/tests/wave1b1_verification.sql`.

**Notes:** finance/support refund overlap deferred to Wave 1C (no such events exist yet) — flagged in
the retention doc. No business authorisation rule changed.

---

## Platform Wave 1B — Audit & Immutable Events ✅
**Status:** migrations `0014`–`0015` applied to live Supabase · all gates passed · typecheck + tests + build pass

Upgrades the Wave-1A `audit_events` stub into the **canonical, reusable, append-only audit service**
(one table, one writer) used by every product/service. Convention: `docs/AUDIT-CONVENTION.md`.

**PR1 — canonical schema + immutability (`0014`):** enums `audit_actor_type` (9 values),
`product_context` (platform/cookbook/farmers_market), `audit_source_application` (7 values).
Additive columns on `audit_events`: actor type/role/merchant, parent entity, product_context,
source_application, reason code/text, before/after_summary, metadata, request/correlation/operation
ids, `idempotency_key` (+partial unique), `supersedes_event_id`, ip/user_agent, `schema_version`
(1A rows=1). `occurred_at` deliberately **not** added — `created_at` already serves it.
**Defence-in-depth immutability:** a BEFORE UPDATE/DELETE/TRUNCATE trigger blocks mutation for
**every** role incl. service-role, plus revoke of the **`TRUNCATE`/`REFERENCES`/`TRIGGER`** grants the
0012 hardening had missed on `authenticated` (a real immutability hole — TRUNCATE bypasses RLS).

**PR2 — canonical writer (`0015`):** `record_audit_event(...)` — the single SECURITY DEFINER,
internal-only (no anon/authenticated grant) append-only writer. Validates domain-oriented action
names (rejects UI-style), rejects secret-bearing + >16KB payloads, derives `actor_type`/`actor_role`
from `platform_staff`/`merchant_staff`/`drivers`, **never fabricates a uid** for system actors,
idempotent via `idempotency_key`. The 1A `_record_audit` is now a thin shim delegating here, so every
existing identity RPC auto-emits canonical `schema_version=2` events with **no per-RPC edits** — no
competing audit functions. Audit insert shares the business transaction (can't commit without it).

**PR3 — verification + docs:** `docs/AUDIT-CONVENTION.md` (action naming, actor model, immutability,
idempotency, payload hygiene); `lib/audit-actions.ts` (pure validator mirroring the DB rule) + tests;
`supabase/tests/wave1b_verification.sql`.

**Gates (verified on live DB):** UPDATE/DELETE/**TRUNCATE** blocked even for the privileged
connection; canonical write via shim → `2/platform/database_rpc`; idempotent (same key → 1 row);
secret + oversize + UI-name + malformed-action all rejected; system actor stored with `null`
actor_user_id (no fabrication); human type without uid rejected; **attribution proven** — a real
super_admin invite yields `actor_type=platform_staff, actor_role=super_admin,
action=platform_staff_invite.created`; the 2 legacy 1A rows remain valid.

**Preflight note:** found + closed the missing `TRUNCATE` grant on `authenticated` (immutability
hole from Wave 1A). Documented magic-link smoke check: `abidoyedimeji@gmail.com` exists + confirmed +
`super_admin`; auth callback/middleware intact.

---

## Platform Wave 1A — Identity & Organisations ✅
**Status:** migrations `0011`–`0013` applied to live Supabase · all four gates passed · typecheck + 11/11 tests + `next build` pass

First platform-backbone wave: **database-backed roles replacing the temporary `ADMIN_EMAILS`
allowlist** (ADR 0009). Governed by `PLATFORM-EXECUTION-PLAN.md` §Wave 1A and `PLATFORM-CONTRACTS.md`.

**PR1 — schema (`0011`):** enums `platform_role`, `merchant_staff_role`, `staff_status`,
`driver_status`, `invite_status`. Tables `platform_staff`, `platform_staff_invites`,
`merchant_organisations`, `merchant_staff`, `merchant_staff_invites`, `drivers`, plus a
Wave-1B-compatible `audit_events` stub and a Wave-1D `notification_outbox` stub. Additive
`merchants.merchant_organisation_id` (nullable). Partial-unique indexes enforce **one active
platform_staff per user** and **one active merchant_staff per (merchant,user)** — a user may be
active at several merchants.

**PR2 — helpers + RLS (`0012`):** SECURITY DEFINER role helpers (`current_platform_role`,
`is_platform_staff`, `is_super_admin`, `is_platform_admin_or_super`, `is_merchant_staff`,
`is_driver`) — definer so RLS policies calling them **don't recurse**. Deny-by-default RLS: self +
admin reads on platform tables; **cross-merchant isolation** via the `merchant_staff` join; anon
grants revoked; authenticated has select-only (no direct writes).

**PR3 — operations (`0013`):** bootstrap + idempotent RPCs (`bootstrap_platform_staff`,
`accept_pending_invites`, `invite_platform_staff`, `change_platform_role`,
`set_platform_staff_status`, `invite_merchant_staff`, `set_merchant_staff_status`, `create_driver`,
`set_driver_status`) — server-side only, each audited to `audit_events` and notified via
`notification_outbox` (no Resend in DB transactions). App: `lib/authz-roles.ts` (pure, tested),
`lib/authz.ts` (server), and `accept_pending_invites` wired into the **shared auth callback**
(`app/auth/callback`) so it runs on **every** authenticated sign-in — marketplace merchants/drivers/
staff never need to visit `/account`; failure is logged and never corrupts the session; the
`/account` call remains an optional idempotent fallback.

**Notification model (terminology, for Wave 1D):** `notification_outbox` here is a **transport/
delivery queue stub** (channel dispatch + retry state) — **not** the canonical notification history.
Wave 1D adds/completes, additively (no rename/drop of the live table): **`notification_events`** =
canonical business notification/event record; **`notification_outbox`** = channel delivery queue +
retry state. Identity operations currently enqueue to the outbox stub as a clean seam.

**Bootstrap result (both approved emails):** `abidoyedimeji@gmail.com` **exists** → seeded
`super_admin` directly; `info@oladimejisultan.org` **absent** → pending `platform_admin` invite,
which attaches to its real `auth.users.id` on first authenticated sign-in. Resolves to
`auth.users.id`, never a display name; rerunnable with no duplicates.

**Gates (all passed, verified on live DB):** migrations apply; bootstrap correct + idempotent;
anon denied (grants) + no direct writes; **cross-merchant isolation proven** (Merchant A admin sees
1 own / 0 other); customer sees 0 staff rows; **no self-escalation** (platform_admin→super_admin
blocked, self-escalate blocked, invite-lower allowed, super_admin invite allowed); invite
acceptance idempotent; role changes recorded in `audit_events`. Verification SQL:
`supabase/tests/wave1a_verification.sql`.

**Notes:** `ADMIN_EMAILS` retained only as a bootstrap fallback (ADR 0009) — the cookbook CMS still
reads it; migrating CMS auth to `platform_staff` is a later, non-blocking step. No cookbook flows
changed except the one additive post-login `accept_pending_invites` call.

---

## The Farmers Market — Phase 0 foundation ✅ (schema + geo + rewards rails)
**Status:** migration `0010` applied to live Supabase · RLS verified via advisors

New local-marketplace surface, built **before** cookbook launch (founder decision) so merchants
in **Dartford / Erith / Eltham** can be onboarded ahead of time. Plan: [`MARKETPLACE.md`](./MARKETPLACE.md).

**Schema (`0010_marketplace_foundation.sql`)** — PostGIS enabled (`extensions` schema); 14 new
tables: `launch_areas`, `merchants`, `merchant_stock_imports`, `market_products`,
`platform_inventory`, `user_addresses`, `market_orders`, `market_order_items`, `market_payouts`,
`referrals`, `merchant_referrals`, `location_waitlist`, `reward_ledger`, `reward_redemptions`.
Money in integer pence + `currency='GBP'`. `geography(Point,4326)` + GiST indexes for the
5-mile radius match. Enums for merchant/connect/order status, fulfilment method, supply type,
referral regime/status, reward kind.

**Key modelling decisions (locked from founder):**
- **Two supply types** — `merchant` (butchers; consigned, ingested from their stock list) and
  `platform` (eggs + water; we hold stock in `platform_inventory`, delivery-only).
- **Driver-collected logistics**, pickup window **04:00–11:00** (`merchants.pickup_window_*`).
- **Reward ledger separates `cashback` (pence) from `points` (non-cash)** via a `kind`
  discriminator — never mixed in one balance (pre-launch 5% cashback vs post-launch points).
- **Two-sided acquisition** — `merchant_referrals` (refer a supplier) + `location_waitlist`
  (vote your town) alongside customer→customer `referrals`.

**Security** — deny-by-default RLS on all 14. Public read only on `launch_areas` (live),
`merchants` (active), `market_products` (available + active/platform). Owner-only on addresses,
orders, referrals, rewards. Public **insert-only** capture on `location_waitlist` +
`merchant_referrals`. Admin/service-role-only (no policy) on stock imports, platform inventory,
payouts. Revoked anon grants on owner-only tables (matches `0006` hardening). Advisors: no
private table exposed to anon; remaining WARNs are the benign RLS-protected-GraphQL-exposure
class (same as cookbook) + intentional insert-only waitlist policy.

**Seed** — 3 launch areas (Dartford/Erith/Eltham) with centroids, `is_live=false` until
merchants onboard.

**Next** — merchant onboarding console (admin), Stripe Connect onboarding link + `account.updated`
webhook, public merchant-referral/location-waitlist capture form. Then Phase A discovery.

---

## Grocery / Shopping Assistant — Level 1–2 ✅
**Status:** complete · typecheck + tests + build pass · DB verified

**Level 1 (shopping list)** — combined ingredient list from structured `recipe_ingredients`;
`ShoppingListExport` (client) offers **Copy list** and **Share to WhatsApp**.

**Level 2 (retailer search links)** — migration `0009` adds `retailers.search_url_template`
(`{q}` placeholder) for the 7 UK supermarkets (Tesco, Sainsbury's, Asda, Morrisons, Iceland,
Ocado, Waitrose). `retailerSearchUrl()` builds a per-ingredient search URL; links are
`rel="…sponsored"` and open the retailer's own site.

**Pages** — `/shop` (assistant landing + supported retailers), `/shop/ingredients` (all 81
ingredients, each with retailer links + export), and a **"Shop the ingredients"** section on
recipe preview pages. Footer + sitemap updated.

**Affiliate-ready, not yet monetised** — `wrapAffiliate()` is a documented no-op passthrough;
drop in Awin/Sovrn wrapping (+ an env publisher id) when a network is approved. No affiliate
network is configured, so links are currently raw. Levels 3–6 remain out of scope.

**Verification** — typecheck clean; 5/5 tests; build passes (41 routes). All 7 retailers have
templates; sample URL builds correctly (`…/search?query=chicken%20breast`).

---

## Blog / SEO Engine ✅
**Status:** complete · typecheck + tests + build pass · DB verified

**Public** — `/blog` (index) + `/blog/[slug]` (article) rendering from `blog_posts` via the
anon RLS-bound client (published-only). Per-article `generateMetadata` (SEO title/desc,
canonical, Open Graph) + **Article JSON-LD**. Conversion CTAs (pre-order + early-access) on
every article. Nav gains Previews + Blog; sitemap now lists published recipes **and** posts.

**Admin** — `/admin/blog` list + create + editor (title, slug, excerpt, HTML body, category,
author, SEO fields, canonical, cover image, publish/unpublish). Publish validates
title+slug+body and stamps `published_at`. Server actions, admin-guarded.

**Seed** (grounded in the captured glossary — not invented): 5 blog categories + 2 published
articles ("The Macro Trinity", "The Lego approach to eating"), measured wording per the
health-claims caveat.

**Verification** — typecheck clean; 5/5 tests; build passes (39 routes). As `anon`: 2
published posts visible, **0 non-published leak**.

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
