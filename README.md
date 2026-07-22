# NutriEat — Breakfast Superfood Cookbook

The digital home for a performance-nutrition cookbook. Starts as a focused **cookbook
sales + early-access + content platform**, then grows into a **meal-planning and
grocery-shopping ecosystem** — in that order, so the launch stays commercially useful
without overbuilding the hard supermarket features before demand is proven.

> **Status: planning.** This repository holds the architecture and launch spec only.
> No application code exists yet. See [`docs/`](./docs).

## Positioning

> Performance nutrition made practical through structured meals, realistic ingredients
> and flexible meal rotations.

Not a pile of random recipes — a structured food system: breakfasts, lunches, superfoods,
smoothies, performance meals, meal rotations, ingredient swaps, and macro/calorie
awareness, built on supermarket-friendly ingredients.

## Editions

| Edition            | Format             | List price | Early-access |
| ------------------ | ------------------ | ---------- | ------------ |
| Breakfast Superfood – Hardback | Physical hardback | $15.99 | −20% |
| Breakfast Superfood – PDF      | Downloadable PDF  | $8.99  | −40% |

> Currency (USD vs GBP vs Stripe auto-conversion) is an **open decision** — the app is
> being designed currency-neutral (`price_cents` + `currency` column). See
> [`docs/ROADMAP.md`](./docs/ROADMAP.md) §Decisions.

## Planned stack

Next.js (App Router) + TypeScript + Tailwind · Supabase (Postgres, Auth, Storage, RLS) ·
Stripe Checkout + webhooks · Vercel · transactional email provider (TBD).

## Docs

| Doc | Covers |
| --- | ------ |
| [`docs/PRODUCT-AND-LAUNCH.md`](./docs/PRODUCT-AND-LAUNCH.md) | Vision, positioning, pricing, audiences, homepage structure, early-access + email journeys, marketing funnel, ads, analytics. |
| [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md) | Routes, stack, data model + RLS, enums, RPCs, API routes, Stripe flow, PDF delivery, auth, SEO, admin. |
| [`docs/SHOPPING-INTEGRATION.md`](./docs/SHOPPING-INTEGRATION.md) | Ingredient → supermarket feature: the 6 levels, what's realistic, retailers, phased design. |
| [`docs/ROADMAP.md`](./docs/ROADMAP.md) | MVP scope, explicit exclusions, 8 build phases, first milestone, and the decisions to lock before building. |

## First milestone

Visitor lands → understands the cookbook → joins early access → completes survey →
views editions → picks physical/PDF → completes a **test** Stripe payment → gets
confirmation → order stored correctly. Everything else layers on after that works.
