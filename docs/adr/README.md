# Architecture Decision Records

Frozen platform-wide rules. **Do not reopen casually during implementation.** Each ADR is short:
Context → Decision → Consequences. Status `Accepted` = ratified and load-bearing; changing one
requires a new superseding ADR, not an inline edit.

The single sentence every developer must be able to answer:
**"Where does shared-platform logic end and Farmers Market-specific logic begin?"**
→ Shared: identity, roles, addresses, money/ledger, payments, notifications, audit, evidence,
recipes, canonical ingredients, geo, content. Market-specific: merchant orgs/stores/staff,
merchant catalogue, sub-orders, fulfilment, driver logistics, returns, settlements, Connect
transfers. The cookbook and the marketplace are two **products** consuming the shared services.

| ADR | Rule |
|-----|------|
| [0001](./0001-nutrieat-is-the-parent-platform.md) | NutriEat is the parent platform |
| [0002](./0002-cookbook-and-market-are-separate-products.md) | Cookbook and Farmers Market are separate products |
| [0003](./0003-one-supabase-project-and-identity.md) | One Supabase project, identity system and shared services |
| [0004](./0004-marketplace-orders-separate-from-cookbook-orders.md) | Marketplace orders remain separate from cookbook orders |
| [0005](./0005-recipes-and-canonical-ingredients-are-shared.md) | Recipes and canonical ingredients are shared |
| [0006](./0006-merchant-products-optionally-link-to-ingredients.md) | Merchant products optionally link to canonical ingredients |
| [0007](./0007-money-is-always-integer-pence.md) | Money is always stored as integer pence |
| [0008](./0008-financial-and-fulfilment-actions-auditable-idempotent.md) | All financial/fulfilment actions are auditable and idempotent |
| [0009](./0009-rls-denies-by-default-no-admin-emails-dependence.md) | RLS denies by default; no permanent `ADMIN_EMAILS` dependence |
