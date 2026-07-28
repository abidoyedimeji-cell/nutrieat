# ADR 0003 — One Supabase project, identity system and shared services

**Status:** Accepted · 2026-07-28

## Context
A single customer should have one account across both products; splitting databases or auth would
fragment identity, rewards, addresses and notifications, and double the operational surface.

## Decision
Both products use **one Supabase project**, **one Supabase Auth** identity, and **one set of shared
services** (profiles, addresses, roles, rewards ledger, referrals, payments, notifications, audit,
recipes, ingredients, content, geo). One account works everywhere.

## Consequences
- Identity, addresses and notification preferences are **platform** tables, not product tables.
- Rewards/credits are one ledger (see ADR 0007/0008); notifications are one service.
- Migrations are a single ordered sequence for the whole platform.
- RLS + roles must scope access per product/actor within the shared project (see ADR 0009).
