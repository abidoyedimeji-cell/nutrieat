# NutriEat

The digital home for **My Healthy Cookbook Recipe For You: Breakfast, Lunch, Smoothies and
Superfoods** — a performance-nutrition cookbook. (App/domain identity: *NutriEat*; the full
title is the book's cover + SEO name.) Starts as a focused **cookbook sales + early-access +
content platform**, then grows into a **meal-planning and grocery-shopping ecosystem** — in
that order, so the launch stays commercially useful without overbuilding the hard
supermarket features before demand is proven.

> **Status: planning.** This repository holds the architecture and launch spec only.
> No application code exists yet. See [`docs/`](./docs).

## Positioning

> Performance nutrition made practical through structured meals, realistic ingredients
> and flexible meal rotations.

Not a pile of random recipes — a structured food system: breakfasts, lunches, superfoods,
smoothies, performance meals, meal rotations, ingredient swaps, and macro/calorie
awareness, built on supermarket-friendly ingredients.

## Editions (prices locked, GBP, UK-first)

| Edition          | Format            | Price   | Early-access |
| ---------------- | ----------------- | ------- | ------------ |
| PDF Edition      | Downloadable PDF  | £9.99   | −40%         |
| Hardback Edition | Physical hardback | £17.99  | −20%         |
| Hardback + PDF Bundle | Both         | £24.99 (excl. shipping) | — |

- **Currency & shipping:** GBP (£), UK-first. Hardback ships **UK £3.99 (1–2 days)** /
  **International £8.99 (3–5 days)**, printed & fulfilled by a distributor; PDF sold
  digitally worldwide. Money
  stored as `price_cents` + `currency = 'GBP'`. Policy: no change-of-mind refunds *(with
  statutory-rights caveat — see ROADMAP)*.
- **Meal claim (source of truth):** **40 core meals**, supported by smoothies, functional
  snacks, supplements, ingredient swaps and three two-week meal plans. *(The old "28"
  figure is retired.)*

See [`docs/ROADMAP.md`](./docs/ROADMAP.md) §Decisions for the full locked/pending list.

## Planned stack

Next.js (App Router) + TypeScript + Tailwind · Supabase (Postgres, Auth, Storage, RLS) ·
Stripe Checkout + webhooks · Vercel · transactional email provider (TBD).

## Docs

| Doc | Covers |
| --- | ------ |
| [`docs/PRODUCT-AND-LAUNCH.md`](./docs/PRODUCT-AND-LAUNCH.md) | Vision, positioning, pricing, audiences, homepage structure, early-access + email journeys, marketing funnel, ads, analytics. |
| [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md) | Routes, stack, data model + RLS, enums, RPCs, API routes, Stripe flow, PDF delivery, auth, SEO, admin. |
| [`docs/SHOPPING-INTEGRATION.md`](./docs/SHOPPING-INTEGRATION.md) | Ingredient → supermarket feature: the 6 levels, what's realistic, retailers, phased design. |
| [`docs/COOKBOOK-CONTENT.md`](./docs/COOKBOOK-CONTENT.md) | The actual book content: manifesto, founder bio, structure, glossary, Top-5 ingredient tables (DB seed), micronutrient profiles, sample meals, 20 smoothies, 20 superfoods. |
| [`docs/STATUS.md`](./docs/STATUS.md) | Living status: completion by area, critical path to first revenue, sprint sequence, remaining non-code blockers. |
| [`docs/ROADMAP.md`](./docs/ROADMAP.md) | MVP scope, explicit exclusions, 8 build phases, first milestone, and the locked/pending decisions. |

## First milestone

Visitor lands → understands the cookbook → joins early access → completes survey →
views editions → picks physical/PDF → completes a **test** Stripe payment → gets
confirmation → order stored correctly. Everything else layers on after that works.
