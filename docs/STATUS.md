# NutriEat — Project Status

Living status snapshot. Planning is near-complete; the work ahead is execution.
See [`ROADMAP.md`](./ROADMAP.md) for scope/phases/decisions, [`ARCHITECTURE.md`](./ARCHITECTURE.md)
for the technical design, [`COOKBOOK-CONTENT.md`](./COOKBOOK-CONTENT.md) for content.

## Overall: ~40%

The number is dominated by planning being done and execution being at zero. Read the two
axes separately:

- **Planning / design:** ~90–95% — essentially complete.
- **Execution (code, content authoring, assets):** ~5–10%.

| Area | Progress | Note |
| ---- | -------: | ---- |
| Product strategy | 95% | |
| Technical architecture | 95% | |
| Database design | 90% | designed, not implemented |
| Marketing strategy | 90% | |
| Cookbook planning | 85% | |
| Smoothies content | 100% | authored (20); not yet data/pages |
| Superfoods content | 100% | authored (20); not yet data/pages |
| Core meals content | ~25% | structure 100%; ~16/40 sampled, 6 with full method |
| Website development | 0% | |
| Database implementation | 0% | |
| Stripe implementation | 0% | |
| Authentication | 0% | Phase 6 (not MVP) |
| Blog content | 0% | ~20–30 SEO articles wanted |
| Marketing assets | ~10% | 2 designed sections exist |
| Testing | 0% | |
| Launch readiness | ~0% | |

> "100%" on smoothies/superfoods means **content authored**, not **shipped** — they still
> need to become `recipe_previews` rows + page assets in Storage.

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

- **Sprint 1 — Foundation:** Next.js + Supabase + Tailwind; schema, RLS, RPCs, enums,
  storage; Stripe wiring; public landing + early-access flow.
- **Sprint 2 — Commerce:** cookbook product page; PDF + hardback purchasing; secure PDF
  delivery; physical order management.
- **Sprint 3 — Content:** finish 40 core meals + nutrition; populate recipes/ingredients/
  meal plans; first 10–20 SEO articles. *(Runs in parallel with Sprints 1–2 where possible
  — writing meals needs no code.)*
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
