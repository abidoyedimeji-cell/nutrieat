# NutriEat

Cookbook commerce + content platform. A cookbook you can buy, a blog engine that
drives SEO demand toward it, and a shopping assistant that turns recipe ingredients
into supermarket baskets.

> **Status: planning.** This repository currently holds the architecture spec only.
> No application code has been written yet. See [`docs/`](./docs) for the design.

## What this is

- A **landing + early-access funnel** (email capture → survey) to build an audience
  pre-launch.
- A **cookbook product page** with **Stripe pre-order checkout** (digital, one-time).
- A **blog + recipe-preview SEO engine** to capture search demand and route it to the
  cookbook.
- A **shopping assistant** (later phase) that maps recipe ingredients to UK supermarkets
  via affiliate deep-links.

## Planned stack

| Layer     | Choice                                             |
| --------- | -------------------------------------------------- |
| Framework | Next.js (App Router) + TypeScript                  |
| Hosting   | Vercel                                             |
| Database  | Supabase (Postgres + Row Level Security)           |
| Payments  | Stripe Checkout + webhooks                         |
| Auth      | Supabase Auth (Phase 2 — accounts/downloads)       |
| Email     | Transactional provider (Resend/Postmark) — Phase 1 |

## Docs

- [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md) — full MVP architecture: pages, data
  model with RLS, RPCs, API routes, Stripe flow, SEO, build phases, env vars.
- [`docs/SHOPPING-INTEGRATION.md`](./docs/SHOPPING-INTEGRATION.md) — the ingredient →
  supermarket shopping feature: what's realistic, what needs partnerships, the phased
  design.

## Build phases (summary)

- **Phase 1 (MVP):** landing → survey → cookbook page → Stripe checkout → blog SEO engine.
- **Phase 2:** user accounts, order history, digital download access, private previews.
- **Phase 3:** shopping lists, meal-plan dashboard, grocery affiliate links, subscription.
