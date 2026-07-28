# ADR 0001 — NutriEat is the parent platform

**Status:** Accepted · 2026-07-28

## Context
NutriEat began as a cookbook site. It is growing into a cookbook product **and** a local
marketplace (Farmers Market), with future subscription/commerce modules likely. Building each as a
standalone app would duplicate identity, money, notifications, audit and content.

## Decision
NutriEat is a **platform**. Products (Cookbook, Farmers Market, future modules) are built **on top of
shared platform services**, not as independent applications. New capability is added as "another
product on the platform," never as a fork.

## Consequences
- A shared-services layer (identity, roles, money/ledger, payments, notifications, audit,
  evidence, recipes, ingredients, geo, content) is a first-class deliverable.
- Cross-cutting concerns are solved **once**; products consume them.
- Every design question is asked as "what does the *platform* provide?" before "what does this
  product need?"
