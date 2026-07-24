# NutriEat — Project Status

Living status snapshot. Planning is near-complete; the work ahead is execution.
See [`ROADMAP.md`](./ROADMAP.md) for scope/phases/decisions, [`ARCHITECTURE.md`](./ARCHITECTURE.md)
for the technical design, [`COOKBOOK-CONTENT.md`](./COOKBOOK-CONTENT.md) for content.

## Overall: ~55% — execution underway

The project has moved beyond planning into execution.

| Area | Progress | Note |
| ---- | -------: | ---- |
| Product strategy | 100% | |
| Technical architecture | 95% | |
| Database design | 95% | recipe tables now import-ready (migration 0005) |
| Website foundation | 90% | Sprint 1 + `/cookbook` product page |
| Commerce | 85% | Sprint 2 built + verified: product page, checkout, webhook, entitlements, fulfilment, env-driven Resend emails (verified sender `oladimejisultan.org`). Remaining: live card-payment test on the deployed env |
| Core meal content | 30% | 12/40 designed spreads delivered; not yet transcribed |
| Smoothies | 100% | 20 authored (designed spreads) |
| Superfoods | 100% | 20 authored (designed spreads) |
| Marketing strategy | 95% | |
| Database implementation | ~75% | migrations + RLS + RPCs + seed + recipe-schema-ready written & build-verified; not yet applied to a live project |
| Authentication + accounts | 90% | Supabase magic-link auth, /account (orders + downloads), claim + redeem RPCs, launch-day-gated PDF delivery. Verified. Pending: Supabase redirect allowlist + PDF upload |
| Blog content | 0% | ~20–30 SEO articles wanted |
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
- **Sprint 3 — Content Engine (new):** transform **all** designed spreads (40 meals + 20
  smoothies + 20 superfoods) into structured data in **one clean import**, plus a **Cookbook
  CMS** to manage content as data (reusable for future volumes / members-only). Runs after
  commerce — not seeded piecemeal.
- **Sprint 4 — Growth:** Meta + YouTube campaigns; search indexing; collect leads, surveys,
  pre-orders.

After that: shopping assistant, customer dashboards, grocery integration — added on real
demand, not assumptions.

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
