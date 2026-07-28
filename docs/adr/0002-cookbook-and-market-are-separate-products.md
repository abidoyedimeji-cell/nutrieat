# ADR 0002 — Cookbook and Farmers Market are separate products

**Status:** Accepted · 2026-07-28

## Context
The two products have materially different lifecycles: the cookbook is marketing/SEO/book-sales; the
marketplace is commerce/merchants/drivers/routes/returns/settlement. Cluttering the cookbook with
logistics (or vice versa) would harm both.

## Decision
Cookbook and Farmers Market are **separate products** with separate surfaces (intended subdomains
`cookbook.*` and `market.*`) and separate domain logic, sharing the platform backbone underneath.
The cookbook never carries logistics; the marketplace never carries book-marketing concerns.

## Consequences
- Front-ends may split by subdomain/route-group later; the shared DB + services make this a low-risk
  app-structure decision, not a data decision.
- Feature flags gate marketplace surfaces independently of the cookbook.
- A developer must always know which product a given page/flow belongs to, and which shared service
  it calls.
