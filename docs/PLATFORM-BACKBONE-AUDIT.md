# NutriEat — Platform Backbone Audit (Phase 1)

**Premise (confirmed reframe): NutriEat is a *platform*, not a cookbook app.** The Cookbook and
the Farmers Market are two **products** on one shared backbone; future subscription/commerce
modules are more products. Every recommendation below favours **reusable platform services** that
serve all products without schema redesign.

Scope: infrastructure only — **ignore feature pages, UI, styling.** Source of truth: migrations
`0001`–`0010` + app code (audited this session) and the four `MARKETPLACE-*.md` specs. No code in
this phase.

---

## 0. The platform model (target)

```
                         NutriEat Platform
   ┌──────────────────────────┴──────────────────────────┐
   Cookbook  (cookbook.nutrieat.co.uk)     Farmers Market (market.nutrieat.co.uk)
   marketing · SEO · book sales            commerce · merchants · drivers · routes
   ┌──────────────────────────┴──────────────────────────┐
                    Shared Platform Services
   Identity · Accounts · Addresses · Roles · Rewards ledger · Referrals ·
   Payments · Notifications · Audit · Evidence/Media · Recipes · Ingredients ·
   Content/CMS · Geo · Analytics
```

**Data-flow direction (one way):** `Recipe → Ingredient → Local availability → Merchant catalogue
→ Basket → Checkout`. The Farmers Market **consumes** cookbook recipe/ingredient data; the cookbook
never carries logistics. The single biggest missing link today: **`market_products` has no
`ingredient_id`** — the join that makes "shop this recipe locally" work. Add it (nullable FK) so the
marketplace reads the existing ingredient graph rather than duplicating it.

**App-structure implication (decision, not built):** one repo, shared server/data packages, two
front-ends on subdomains (or Next route-groups with host-based routing). The **database + services
are shared regardless** of how the front-ends are split — so backbone work is identical either way
and should proceed now; the subdomain split is a later, low-risk app decision.

---

## 1. Current state — what actually exists (verified)

**Built (cookbook product):** landing/early-access/survey funnel; `/cookbook` commerce (Stripe
Checkout, order-first, env Price IDs); webhook with signature verify + `payment_events` idempotency;
orders/order_items/entitlements; magic-link auth (`@supabase/ssr`) + `/account` (orders, downloads,
guest-claim); launch-day-gated PDF via `redeem_download` + private `cookbook-pdf` bucket + signed
URLs; Content Engine + CMS (recipes/ingredients/meal-plans/blog, admin-gated); public recipe
previews; blog/SEO; grocery L1–2 (retailer search + list export). Resend email (`lib/email.ts`).

**Schema-only (marketplace foundation, `0010`):** 14 tables (`launch_areas`, `merchants`,
`merchant_stock_imports`, `market_products`, `platform_inventory`, `user_addresses`,
`market_orders`, `market_order_items`, `market_payouts`, `referrals`, `merchant_referrals`,
`location_waitlist`, `reward_ledger`, `reward_redemptions`) + PostGIS. **Zero marketplace app code.**

**Specified, not built:** everything in `MARKETPLACE-ARCHITECTURE.md` §3–§14 (≈48 tables, ~30 enums,
8 state machines, RPC/webhook/job plan, Connect, evidence, returns, settlements).

**Authorization reality:** the *only* auth mechanism is the `ADMIN_EMAILS` env allowlist
(`lib/admin-allowlist.ts`). **No roles table, no `profiles.is_admin`.** This is the #1 backbone gap.

---

## 2. 29-workstream implementation audit

Legend: ✅ done · 🟨 partial · ⬜ not started · ♻️ needs redesign for platform. "Gap" columns list
what's missing at the *infrastructure* layer.

| # | Workstream | State | Missing schema / enums / RPC / RLS / storage / jobs / integrations |
|---|-----------|:----:|--------------------------------------------------------------------|
| 1 | Product/commercial decisions | 🟨 | Cookbook locked; **market decisions locked in specs but 5 P0s open** (super-admin identity, service-fee mapping, delivery/route zones, no-show window, Connect). Doc, not code. |
| 2 | Production infrastructure | 🟨 | Vercel + Supabase live; **missing:** Stripe *live* keys+webhook, Auth callback allowlist, prod error monitoring, backup/migration discipline doc |
| 3 | Cookbook commerce | ✅🟨 | Built; **missing:** live-mode verification (real card), admin order views beyond `/account` |
| 4 | Accounts & digital delivery | 🟨 | Auth + downloads built; **missing:** final PDF upload, release-day email trigger, expired/regenerated-link tests |
| 5 | Cookbook content | 🟨 | ~28 meals unwritten; smoothie/meal detail incomplete; superfood health-claim review outstanding |
| 6 | Content Engine / CMS | ✅🟨 | Built; **missing:** CMS audit trail, DB-backed admin roles (uses allowlist), import integrity checks hardening |
| 7 | Public recipe discovery | ✅🟨 | Previews live; **missing:** related-content, breadcrumbs, structured data completeness, sitemap paid-exclusion verify |
| 8 | Blog & SEO | ✅🟨 | Engine built, 2 posts; **missing:** GSC, sitemap submit, ~20 articles, pillars |
| 9 | Analytics & attribution | ⬜ | **Nothing.** No GA/Vercel Analytics/Meta Pixel/Ads; no funnel/consent. `notification_events`-style event capture absent |
| 10 | Referral & rewards foundation | ⬜ | Tables exist (`referrals`,`reward_ledger`,`reward_redemptions`); **zero logic**; **missing:** `referral_codes`, `merchant_referral_milestones`, `reward_catalogue`, redemption state machine, QR, accrual/reversal RPCs |
| 11 | FM location & waitlist | ⬜♻️ | `launch_areas`/`location_waitlist` exist but **need hub reshape** (Amd 1): `service_zones`, nearest-hub, `waitlist_status`, one-active-per-hub, geocoding integration |
| 12 | Identity, roles, permissions | ⬜ | **Backbone P0.** Missing: `platform_staff`,`merchant_staff`,`drivers`, merchant org/store, `platform_role`/`merchant_staff_role`, role audit, invite/revoke, suspension. Replaces `ADMIN_EMAILS` |
| 13 | Merchant onboarding & portal | ⬜ | Missing: application/approval states, catalogue CRUD, import staging (`merchant_stock_import_rows`), operations queue, `product_images`, Connect onboarding |
| 14 | Platform-owned inventory | 🟨⬜ | `platform_inventory` exists; **missing:** `inventory_movements`, reserved/damaged stock, batch/expiry, cost/margin, wholesale records |
| 15 | Basket & pricing engine | ⬜ | Missing: `baskets`/`basket_items`, fee calc, price snapshot, atomic reserve, dup-submit guard |
| 16 | Marketplace payments & Connect | ⬜ | Missing: `connect_accounts`, `market_payment_events`, `merchant_settlements`/`_holds`/`_adjustments`, `merchant_transfers`, all Connect code |
| 17 | Order/sub-order/item lifecycle | ⬜ | Missing: `merchant_sub_orders`, item fulfilment cols, `item_events`, immutable history, extended `market_order_status` |
| 18 | Merchant picking & evidence | ⬜ | Missing: `evidence_media`, `issue_evidence`, evidence bucket, lock-on-dispute, SLA alerts |
| 19 | Driver collection/delivery | ⬜ | Missing: `routes`,`collection_tasks`,`delivery_tasks`,`route_reconciliations`,`vehicle_reconciliations`, task enums |
| 20 | Customer delivery confirmation | ⬜ | Missing: `delivery_confirmations`/`_items`, `item_issues`+`issue_reason`, driver-present gate |
| 21 | Returns/refunds/liability | ⬜ | Missing: `item_returns`,`return_manifests`/`_items`,`merchant_return_confirmations`,`refund_decisions`,`refunds`,`customer_credits`, liability/refund enums |
| 22 | Settlement & payout reconciliation | ⬜ | Missing: split-settlement math, `settlement_holds`, reconfirmation loop, statements |
| 23 | Support & ops admin | ⬜ | Missing: `customer_support_cases`,`support_messages`, unified admin, queues, fee-override, manual credit |
| 24 | Notifications | 🟨⬜ | Cookbook uses Resend directly; **missing platform service:** `notification_events`, prefs, in-app, dedupe, per-event triggers |
| 25 | Quality/trust/audit | ⬜ | Missing: `audit_events` (append-only), merchant/driver metrics, fraud/duplicate indicators |
| 26 | Marketplace stress-tests | 🟨 | 94 scenarios **specified**; none executed as tests (no test harness for market) |
| 27 | Legal/compliance | 🟨 | Cookbook refund/health caveats documented; **missing:** marketplace T&Cs, merchant agreement, perishable/allergen/food-hygiene, evidence-consent, data-retention, Connect/VAT review |
| 28 | Pilot preparation | ⬜ | Non-code: merchant/wholesaler onboarding, catalogue import, training, beta |
| 29 | Public launch & growth | ⬜ | Depends on all above |

**Summary:** the **cookbook product is ~80% built**; the **marketplace product is ~5% built** (14
tables, no code) but **~95% specified**; the **shared platform backbone is ~30% built** (auth +
money convention + payments idempotency + content exist; roles, audit, notifications-as-a-service,
unified ledger, evidence, geo-zones do not).

---

## 3. The true platform backbone (infrastructure only)

Everything else depends on these. Ordered by how many workstreams they unblock:

| Backbone service | Exists? | Needed for |
|------------------|---------|-----------|
| **B1 Identity & access** (users, profiles, addresses, roles, notif prefs) | auth ✅ / roles ⬜ / addresses schema-only | 12,13,19,23 + all RLS |
| **B2 Audit** (`audit_events` append-only) | ⬜ | every privileged action (10,13,16,21,22,23,25) |
| **B3 Money & ledger** (one representation, `reward_ledger`+`customer_credits`+`reward_catalogue`, pence) | ledger schema-only | 10,16,21,22 |
| **B4 Payments** (Stripe abstraction, unified idempotency, Connect) | 1 acct + `payment_events` ✅ / Connect ⬜ | 3,16,21,22 |
| **B5 Notifications** (`notification_events` + channels) | Resend only | 4,10,13,18,19,20,22,24 |
| **B6 Evidence/media** (buckets, immutable, signed URLs) | `cookbook-pdf`/`recipe-images` ✅ pattern | 18,19,20,21 |
| **B7 Catalogue/product** (cookbook + market products, shared money) | cookbook ✅ / market schema-only | 3,13,14,15 |
| **B8 Order/payment-event** (shared idempotency, separate lifecycles) | cookbook ✅ / market ⬜ | 3,15,16,17 |
| **B9 Geo** (PostGIS hubs, `service_zones`, geocode) | PostGIS ✅ / zones ⬜ | 11,15,19 |
| **B10 Content** (recipes/ingredients/CMS) | ✅ | 5,6,7,15 (ingredient→product join) |

---

## 4. The 20 backbone questions (answered)

1. **DB domains still missing:** identity/roles, merchant org/store, driver, basket, sub-orders,
   item fulfilment, evidence, driver logistics + reconciliation, returns, refund decisions,
   settlements/holds/transfers, Connect accounts, support, notifications, audit, service zones,
   inventory movements, import staging, reward catalogue, referral codes/milestones. (Most are
   *specified* in `MARKETPLACE-ARCHITECTURE.md`, none built beyond `0010`.)
2. **Enums still missing (~30):** all Amendment-1/2 enums — `platform_role`, `merchant_staff_role`,
   `merchant_order_status`, `item_fulfilment_status`, `evidence_type`, task statuses,
   `issue_reason`, `refund_eligibility`, `return_requirement`, `liability`, `refund_status`,
   `refund_review_status`, `return_status`, `payout_status`, `transfer_status`, `waitlist_status`,
   `merchant_suggestion_status`, `route_status`, `vehicle_reconciliation_status`,
   `settlement_hold_status`, `refund_method`, `inventory_status`, `order_type`, `address_type`,
   `service_area_type`, `reward_redemption_status`, `support_case_status`.
3. **Tables still missing:** ~34 net-new beyond `0010` (see §2 rows 10–25 + §3). Plus **extend**
   `market_products`(+`ingredient_id`, status, stock), `market_orders`, `market_order_items`,
   `merchants`, `platform_inventory`, `user_addresses`(→platform), `location_waitlist`,
   `reward_ledger`.
4. **Relationships still missing:** `market_products.ingredient_id → ingredients` (the recipe→
   product bridge); `merchant_sub_orders → market_orders/merchants`; item→sub_order; evidence
   polymorphic refs; settlement→sub_order; return→issue→refund_decision→refund; `merchant_staff`
   join (RLS isolation); address→hub.
5. **State machines still missing:** all 10 in the specs (order, sub-order, item, collection,
   delivery, rejection/issue, return, refund-review, settlement/payout, transfer, route, vehicle,
   referral, reward redemption) — **defined in spec, not enforced in DB/code.**
6. **Audit tables required:** `audit_events` (append-only, universal) + `item_events` (item
   lifecycle) + CMS audit trail. Immutable, no update/delete.
7. **Money ledgers required:** unified `reward_ledger` (cashback pence vs points, `kind`
   discriminator — exists), `customer_credits`, `merchant_settlements`+`settlement_holds`+
   `settlement_adjustments`, `merchant_transfers`, `refunds`, `market_payment_events`. One pence
   representation platform-wide.
8. **Notification tables required:** `notification_events` (platform), notification preferences
   (on profiles/new table), delivery log. Replaces direct Resend calls with a service.
9. **Evidence tables required:** `evidence_media` (immutable), `issue_evidence`,
   `merchant_return_confirmations` (carry evidence refs). One private bucket.
10. **Event logs required:** `audit_events`, `item_events`, `notification_events`,
    `payment_events`/`market_payment_events`, `inventory_movements`, analytics event capture.
11. **Storage buckets required:** existing `cookbook-pdf`(private), `recipe-images`(public); **new**
    `market-products`(public), `market-evidence`(private, signed-URL, immutable).
12. **RLS policies missing:** all marketplace tables need deny-by-default + merchant-staff-join
    isolation, driver-assigned scoping, owner-only customer, finance/support scoping; `platform_staff`
    role-based policies to replace `ADMIN_EMAILS`; audit/evidence insert-only.
13. **RPCs required:** the full §7 set — order create (atomic, reserve, book slot), merchant accept/
    pick/ready, evidence insert, collection/delivery confirm, driver-present confirm (3-level),
    raise issue, request/approve/reconcile return, refund_decision + execute, split-settlement calc,
    payout reconfirm, transfer release, referral accrual/reversal, reward redeem, import validate/
    confirm, geocode/nearest-hub. All SECURITY DEFINER, pinned `search_path`, idempotent.
14. **Edge Functions required:** minimal — prefer RPC + route handlers. Candidates: image
    compression on evidence upload, CSV/XLSX parsing for large imports, QR generation (or do in a
    route handler). Not core backbone.
15. **Background/scheduled jobs required:** auto-confirm fallback (no-show), payout-eligibility +
    reconfirmation sweep, settlement recalculation, notification dispatch/retry, waitlist demand
    rollups, referral-window clearance, import apply, GSC/index monitoring. (Vercel Cron.)
16. **API routes required:** market checkout create, market Stripe webhook (+Connect events),
    Connect onboarding link/return, evidence upload (signed), driver task actions, import upload,
    waitlist/merchant-suggestion capture, notifications read. Cookbook routes already exist.
17. **Stripe Connect objects required:** Express `Account`, `AccountLink`, `account.updated` webhook,
    separate-charge + `Transfer` per merchant, `transfer.*`/`payout.*` events, transfer reversal for
    clawback, `application_fee`/commission retention. `connect_accounts` mirror table.
18. **Resend email flows required:** existing (welcome, order confirmation, refund, PDF release) +
    **new via notification service:** merchant new-order, prep reminder, ready-for-collection, driver
    assignment, out-for-delivery, delivery confirmation, issue alert, return, refund decision, credit,
    settlement update, payout, waitlist invite, referral progress, reward earned, support updates.
19. **Admin modules required (one Platform Admin):** Dashboard · Cookbook · Market · Merchants ·
    Orders · Drivers · Customers · Support · Finance · Content · Analytics · Settings — module-gated
    by `platform_role`. Replaces separate cookbook/market admins.
20. **Reusable platform services to extract:** `identity`, `authz/roles`, `money-ledger`,
    `payments` (Stripe + idempotency + Connect), `notifications`, `audit`, `evidence/media`,
    `catalogue`, `geo`, `content`. These are the packages the reframe implies — build them once,
    both products consume them.

---

## 5. Optimal build order (minimises future schema change)

Rule: **foundational DB before business logic; reusable platform services before product features;
no later work forces a redesign of an earlier migration.** The cookbook content/marketing track
(workstreams 5,7,8) runs **in parallel** — it's independent and mostly built.

**Tier 0 — Platform decisions (unblock everything, no code):** resolve the 5 marketplace P0s
(super-admin identity, service-fee mapping, delivery/route zones, no-show window, Connect enablement)
+ ratify the platform reframe (subdomains, one admin, `ingredient_id` bridge).

**Tier 1 — Backbone data (do first, together — everything depends on them):**
1. **B1 Identity & roles** — `platform_staff`, `merchant_staff`, merchant org/store, `drivers`,
   `platform_role`/`merchant_staff_role`, promote `user_addresses` to a **platform** table
   (+`type`,`nearest_hub_id`), notification prefs. *Replaces `ADMIN_EMAILS`; every RLS policy depends
   on this — build before any table with row ownership.*
2. **B2 Audit** — `audit_events` (append-only). *Referenced by every privileged RPC after.*
3. **B3 Money/ledger unification** — extend `reward_ledger`, add `customer_credits`,
   `reward_catalogue`, `referral_codes`, `merchant_referral_milestones`; lock one pence
   representation. *Before any reward/refund/settlement logic.*
4. **B5 Notifications** — `notification_events` + prefs + service abstraction over Resend. *Before
   any flow that notifies.*
5. **B4/B8 Payments idempotency** — `market_payment_events`; decide shared-vs-separate Stripe event
   ledger (D5). *Before Connect + any money movement.*
6. **B9 Geo** — hubs reshape (`launch_areas` hub fields), `service_zones` (discovery/delivery/
   collection/route), geocode + nearest-hub, `service_area_type`/`address_type`. *Before discovery/
   ordering.*

**Tier 2 — Catalogue & inventory (depends on T1):**
7. **B7 Catalogue** — extend `market_products` (**+`ingredient_id`** bridge, status, stock,
   pack/unit), `product_images`; merchant catalogue CRUD; import staging
   (`merchant_stock_import_rows`). Platform inventory: `inventory_movements`, reserved/damaged/batch.

**Tier 3 — Order lifecycle spine (depends on T1–T2):**
8. **Basket** (`baskets`/`basket_items`, fee calc, snapshot, atomic reserve).
9. **Order → sub-orders → items** (`merchant_sub_orders`, item fulfilment cols, `item_events`,
   extended `market_order_status`, immutable history).

**Tier 4 — Fulfilment & evidence (depends on T3):**
10. **B6 Evidence** — `evidence_media` + `market-evidence` bucket + `issue_evidence`.
11. **Merchant picking** (accept/pick/pack/ready + evidence + SLA).
12. **Driver logistics + reconciliation** (`routes`, `collection_tasks`, `delivery_tasks`,
    `route_reconciliations`, `vehicle_reconciliations`, closure gate).
13. **Delivery confirmation (driver-present) + issues** (`delivery_confirmations`/`_items`,
    `item_issues` + 3 dimensions).

**Tier 5 — Money-out (depends on T4 + T1 money/payments):**
14. **Returns** (`item_returns`, manifests, merchant confirmations).
15. **Refunds + liability** (`refund_decisions`, `refunds`, `customer_credits`).
16. **Stripe Connect + settlements** (`connect_accounts`, split `merchant_settlements`+
    `settlement_holds`+`adjustments`, `merchant_transfers`, reconfirmation).

**Tier 6 — Ops & trust (depends on all):**
17. **Support** (`customer_support_cases`, queues) + **Platform Admin** modules.
18. **Quality/metrics/fraud** (reads audit + events).
19. **Marketplace stress-tests executed** (against the 94 scenarios) + legal/compliance + pilot.

**Parallel track (independent, mostly built):** cookbook content completion (5), recipe discovery
polish (7), blog/SEO + GSC (8), analytics/attribution (9) — none of these block the marketplace
backbone and analytics/audit event capture can share `notification_events`/`audit_events` plumbing.

**Dependency guarantee:** because Identity, Audit, Money, Notifications, Payments-idempotency and Geo
(Tier 1) are built **before** any product feature, and the **`ingredient_id` bridge** + one pence
ledger + one roles model are fixed up front, no Tier ≥2 migration needs to alter a Tier-1 table's
shape — later work only *adds* tables/columns, never redesigns the backbone.

---

## 6. Immediate recommendation

1. **Ratify the platform reframe** (this doc's §0) — one admin, one ledger, one notification service,
   `ingredient_id` bridge, subdomains later.
2. **Answer the 5 marketplace P0s** (Tier 0) — they gate Tier 1.
3. **Build Tier 1 as the first migration wave** (`0011`–`0016` per `MARKETPLACE-ARCHITECTURE.md` §12,
   reordered to lead with identity/audit/money/notifications/payments/geo).
4. Cookbook completion + analytics proceed **in parallel** — no dependency.

*No migrations or application code until this backbone plan + the reframe are reviewed and approved.*
