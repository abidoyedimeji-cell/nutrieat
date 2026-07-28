# NutriEat — Project Status

Living status snapshot. Planning is near-complete; the work ahead is execution.
See [`ROADMAP.md`](./ROADMAP.md) for scope/phases/decisions, [`ARCHITECTURE.md`](./ARCHITECTURE.md)
for the technical design, [`COOKBOOK-CONTENT.md`](./COOKBOOK-CONTENT.md) for content.

> **Platform Wave 1A (Identity & Organisations) — ✅ COMPLETE** (migrations 0011–0013, applied +
> gated). Database-backed roles (`platform_staff`/`merchant_staff`/`drivers`) now exist, replacing
> sole reliance on `ADMIN_EMAILS`; super-admin bootstrapped to real `auth.users.id`; cross-merchant
> isolation proven.
>
> **Platform Wave 1B (Audit & Immutable Events) — ✅ COMPLETE** (migrations 0014–0016, applied +
> gated). Canonical append-only audit service: one writer (`record_audit_event`), defence-in-depth
> immutability (UPDATE/DELETE/TRUNCATE blocked for all roles), attributable + idempotent, secret/
> oversize-rejecting. **1B.1 closeout** added restricted role-scoped reads (`get_audit_events`),
> closed a writer actor-spoofing grant hole, `event_category` classification, and Wave-1A audit
> enrichment. Convention [`AUDIT-CONVENTION.md`](./AUDIT-CONVENTION.md); retention
> [`AUDIT-RETENTION.md`](./AUDIT-RETENTION.md).
>
> **Platform Wave 1C (Money & Ledger Foundation) — ✅ COMPLETE** (migration 0017, applied + gated).
> Append-only, idempotent double-entry cash ledger (`financial_accounts`/`journals`/`postings`, pence
> GBP), balance-enforced + reconcilable, internal-only writer, finance-gated reads; **points stay in
> `reward_ledger`, never mixed with cash**. Money model in [`MONEY-MODEL.md`](./MONEY-MODEL.md).
> Marketplace backbone continues per the wave plan; **Wave 1D (Notifications) awaits review**.

## Overall: ~55% — execution underway

The project has moved beyond planning into execution.

| Area | Progress | Note |
| ---- | -------: | ---- |
| Product strategy | 100% | |
| Technical architecture | 95% | |
| Database design | 95% | recipe tables now import-ready (migration 0005) |
| Website foundation | 90% | Sprint 1 + `/cookbook` product page |
| Commerce | 85% | Sprint 2 built + verified: product page, checkout, webhook, entitlements, fulfilment, env-driven Resend emails (verified sender `oladimejisultan.org`). Remaining: live card-payment test on the deployed env |
| Content Engine + CMS | 90% | Admin CMS built (recipes/ingredients/meal-plans), idempotent import run, public previews live; ~28 meals still to author |
| Core meal content | 30% | 12/40 imported as drafts (1 with captured detail); 28 outstanding |
| Smoothies | 100% authored / imported | 20 imported as incomplete drafts (lists only) |
| Superfoods | 100% authored / imported | 20 imported complete; 3 published as public previews |
| Marketing strategy | 95% | |
| Database implementation | ~75% | migrations + RLS + RPCs + seed + recipe-schema-ready written & build-verified; not yet applied to a live project |
| Authentication + accounts | 90% | Supabase magic-link auth, /account (orders + downloads), claim + redeem RPCs, launch-day-gated PDF delivery. Verified. Pending: Supabase redirect allowlist + PDF upload |
| Blog / SEO engine | 85% | Blog system built (public pages, SEO + JSON-LD, admin CMS); 2 seed articles published. Remaining: author ~20 articles |
| Marketing assets | ~15% | smoothie + superfood + 12 meal spreads exist |
| Testing | 0% | |
| Launch readiness | ~55% | |

> "100%" on smoothies/superfoods and the 12 meals means **content designed** (JPG spreads),
> not **imported** — they become structured `recipes`/`ingredients` data in the Content
> Engine sprint (Phase 3), in one pass.

## Critical path to first revenue (narrow)

To accept an early-access pre-order, only this is needed:

```
landing → early-access form → cookbook page → Stripe checkout → webhook → confirmation email
                                                                   (PDF entitlement gated to launch day)
```

**Not** required for first revenue: blog, recipe DB, customer accounts, shopping assistant,
or all 40 meals finished. Those are parallel or post-launch.

**Key insight:** because pre-orders deliver the PDF on **launch day**, the build and the
content authoring run **in parallel**. The 40 meals gate launch-day *delivery*, not the
funnel going live. Open the funnel, run ads, collect pre-orders while content is finished.

## Sprint sequence (agreed, with parallelisation)

- **Sprint 1 — Foundation ✅:** Next.js + Supabase + Tailwind; schema, RLS, RPCs, enums;
  public landing + early-access flow; recipe tables made import-ready.
- **Sprint 2 — Commerce ✅:** `/cookbook` product page; PDF + hardback + bundle purchasing;
  server-side Stripe checkout + idempotent webhook; launch-day-locked PDF entitlements;
  physical order/shipping capture; Resend confirmation emails. Build + DB-flow verified.
  *(Real recipe/smoothie previews deferred to the Content Engine sprint — they need the
  content import; not on the commerce critical path.)*
- **Sprint 3 — Content Engine + CMS ✅ (partial content):** Cookbook CMS built (admin
  allowlist, recipes/ingredients/meal-plans CRUD, publish/preview); idempotent import ran
  (20 superfoods complete, 20 smoothies + 12 meals as incomplete drafts); public previews
  live. Remaining: author the ~28 missing meals and complete smoothie/meal detail via the
  CMS, then publish more previews.
- **Sprint 4 — Growth:** Meta + YouTube campaigns; search indexing; collect leads, surveys,
  pre-orders.

- **Grocery / Shopping Assistant — Level 1–2 ✅:** shopping-list export (copy / WhatsApp) +
  per-ingredient supermarket search links across 7 UK retailers; `/shop`, `/shop/ingredients`,
  and a "Shop the ingredients" section on recipe pages. Affiliate-ready (raw links until a
  network is approved). Levels 3–6 out of scope.

All four growth phases (Accounts+Delivery, Content+CMS, Blog, Grocery L1–2) are built.
Remaining is content depth (the ~28 meals, more blog articles) and monetisation config
(affiliate network) — added on real demand, not assumptions.

## Non-code blockers still open

- **Named distributor + print-ready files** — gates *hardback* checkout going live (PDF path
  is unblocked).
- **Legal review before public launch** — refund policy wording and health-claims wording
  (both caveats documented in [`ROADMAP.md`](./ROADMAP.md)).
- **Email (Resend)** — account + templates (welcome, purchase confirmation, download access).
- **Content** — the remaining ~24 of 40 core meals with full nutrition data.

## Locked decisions

All commercial decisions are locked except **bundle already set (£24.99)** — remaining
open items are the distributor/print files, legal review, and email setup above. Full list
in [`ROADMAP.md`](./ROADMAP.md) §Decisions.
