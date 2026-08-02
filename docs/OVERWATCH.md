# NutriEat — Overwatch Report (Baseline)

> **Role:** continuous "future-plan overwatch" — each cycle diff the trunk against intended
> scope and report what is missing across **UI → route → resolver → RPC → SQL → RLS → enums →
> tables → migrations**, flag dead/stale/placeholder code and UI, run (or trace) a ghost-account
> flow per role, and cross-reference open PRs.
>
> **Cycle:** 001 · **Date:** 2026-08-02 · **Trunk SHA:** `e4c35a8` · **Method:** static analysis
> (3 parallel layer inventories + manual role trace). Live ghost execution blocked — see §0.

---

## 0. Ground truth (read this first)

| Fact | Value | Why it matters |
| ---- | ----- | -------------- |
| **Default branch** | `claude/cookbook-mvp-architecture-8oma2q` | **There is no `main`.** The mandate "always look at main" has no target — trunk is the cookbook-mvp branch. |
| **Overwatch branch** | `claude/ciri-os-repo-oversight-rp0knv` @ `e4c35a8` | Currently **identical to trunk** (merge-base == both heads). Nothing to diff yet; this is the baseline. |
| **Open PRs** | **0** | All 15 historical PRs (Wave 1A→1C.1) merged into trunk. Nothing in flight to cross-reference this cycle. |
| **Stale branches** | **15** `wave1a-pr1` … `wave1c1-prc` on origin | Merged but never deleted — remote clutter. |
| **Live DB** | **None for this repo** | 4 Supabase projects exist under the org; the one named **CIRI** is a *different app* (services/studio/rental marketplace). NutriEat's 46-table schema is **deployed nowhere**. |
| **Ghost flows** | **Traced, not run** | No deployed DB ⇒ cannot create ghost auth users / exercise RLS live. Needs a target project (see §6 action). |

> ⚠️ **Naming mismatch to resolve:** the mandate calls the repo *ciri-os*; this repo is
> *nutrieat*, and the Supabase project *CIRI* hosts an unrelated product. Confirm whether NutriEat
> should deploy to a new project, or whether "ciri-os" refers to a different repo, before any live
> ghost run.

---

## 1. The shape of the gap

The backend is built **far ahead** of the product. Migrations 0011–0022 (identity/orgs, audit,
double-entry financial ledger, points, marketplace) are disciplined, deny-by-default, and
well-tested — but almost none of it is reachable through a route, resolver, or UI.

```
 Built & wired (reachable):   visitor · customer · admin(CMS)      ← cookbook commerce + content
 Built, NOT wired (schema/RPC only):  platform_admin · operations · finance · support ·
                                      merchant_admin · merchant_manager · merchant_picker ·
                                      driver · the entire Farmers Market storefront
```

Of ~9 roles the schema models, **3 are reachable** through the product. The rest have full tables +
RLS + (for staff) operation RPCs, and **zero** routes/resolvers/UI/onboarding.

---

## 2. Findings by severity

### P0 — Structural (capability built, not connected)

1. **Commerce + marketplace transaction layer is schema + read-RLS only — no write path.**
   `orders`, `order_items`, `market_orders`, `market_order_items`, `referrals`,
   `reward_redemptions`, `merchant_organisations` all have owner-read RLS but **no INSERT path**.
   0004's header promised commerce RPCs ("arrive with the commerce sprint") that never landed
   through 0022. Cookbook orders work *only* because the Stripe webhook writes them with the
   service-role client, bypassing RLS.

2. **The real money path bypasses the ledger and the audit log.**
   `app/api/checkout/create/route.ts` and `app/api/stripe/webhook/route.ts` write `orders` /
   `order_items` / `download_entitlements` / `payment_events` directly. They **never call**
   `post_financial_journal` (0017) or `record_audit_event` (0016) — both orphans. So the
   Wave 1C/1C.1 double-entry ledger records **£0 of real revenue**, and no `audit_events` row is
   produced for any payment. **ADR-0008** ("financial & fulfilment actions auditable + idempotent")
   is satisfied in *schema* but not in the *live money path*.

3. **The RBAC backbone has no UI enforcement path.**
   `platform_staff` / `merchant_staff` / `drivers` + 8 roles (0011–0013) are unreachable: no
   merchant portal, no driver app, no ops/finance/support dashboard, no `/market` storefront route.
   Onboarding RPCs (`invite_platform_staff`, `invite_merchant_staff`, `create_driver`, …) are all
   orphaned.

4. **Admin still gates on `ADMIN_EMAILS`, contradicting ADR-0009.**
   `lib/admin.ts:11` (`requireAdminPage`/`assertAdmin`) uses the env allowlist as the *sole* admin
   gate — exactly what ADR-0009 ("no admin-emails dependence") and the purpose-built `platform_role`
   system (0011–0013) were meant to replace. `lib/authz.ts` (the DB-role reader) is imported by
   **nothing**. CMS write actions also emit no `audit_events`.

### P1 — Orphans (dead / unreachable but shipped)

- **Fully-orphaned tables** (RLS on, no policy, no writer, no seed): `merchant_stock_imports`,
  `platform_inventory`, `market_payouts` (0010).
- **~23 orphan RPCs** — every identity-ops, audit, and ledger function except
  `current_platform_role` + `accept_pending_invites`. Never called from `app/` or `lib/`.
- **Dead lib module:** `lib/authz.ts` — `getPlatformRole`/`isPlatformStaff`/`acceptPendingInvites`
  never imported (app calls `supabase.rpc(...)` directly).
- **Orphan resolvers:** `getRecipeShoppingList` (`lib/shopping.ts:46`), `sendRefundConfirmation` /
  `sendPdfReleaseEmail` (`lib/email.ts`) — no refund or launch-day flow wired.
- **Superseded RPC:** `get_public_recipe` (0004) — app reads recipes via `.from('recipes')`; two
  parallel read paths, RPC is dead / drift risk.
- **`profiles` never populated** — no `handle_new_user` trigger, no INSERT policy. Table is dead as
  written (account flow uses `auth.uid()` directly, so functionally isolated).
- **Never-populated content tables:** `blog_posts`, `blog_categories` (no articles seeded),
  `shopping_links`, `meal_plan_recipes`, `ingredient_substitutions`.
- **Customer wallet built but hidden:** `get_my_credit_balances` / `get_my_points_balances` exist;
  `/account` surfaces neither.

### P2 — UI placeholders & small gaps

- **No `/admin/meal-plans/new`** — meal plans can be edited but not created via UI (recipes/
  ingredients/blog all have `/new`).
- **`/api/surveys` has no caller** — native `submit_cookbook_survey` fully built; `/survey` only
  renders a Google-Form iframe or a "Survey coming shortly" placeholder (`app/survey/page.tsx:34`).
- **`/checkout/success` ignores `session_id`** — shows "Payment received" unconditionally; order
  truth depends entirely on the webhook.
- **Legal pages are explicit drafts** — `privacy` / `terms` / `refund-policy` carry
  "Draft — pending final legal review" + "placeholder copy" (blocks public launch per STATUS).
- **PDF launch-day redeem gate deferred** — `app/api/stripe/webhook/route.ts:174` notes the
  redeem-time gate lands "in a later sprint."

### P3 — Hygiene / drift

- **Dead enum value:** `financial_account_kind.customer_credit_liability` (superseded by 0018 split).
  **Unpopulated enum:** `involvement_level` — column is enum but the survey stores the concept as
  `text`; `create_cookbook_lead` never sets it (enum-vs-text mismatch).
- **Unreachable enum states:** most `order_status` / `fulfilment_status` / `market_order_status`
  transitions, `invite_status.expired`, `reward_status.{expired,reversed}`, `content_status.scheduled`
  — no writer ever sets them.
- **Migration churn:** 0016 redefines 6 functions from 0013; 0021 exists solely to hotfix a
  null-coalesce bug in 0020; `record_audit_event` grant re-revoked 0015→0016, more re-revokes in 0022.
  Candidates for a future squash.
- **Cosmetic:** columns named `*_cents` while docs say "pence" (functionally identical, GBP-locked).
- **15 stale merged `wave-*` branches** on origin — safe to delete.

---

## 3. Layer inventory (reference)

| Layer | Count | Reachable from product | Orphaned / unwired |
| ----- | ----: | ---------------------- | ------------------ |
| Migrations | 22 | — | commerce-RPC promise (0004) unfulfilled |
| Enums | 33 | ~all attached | 1 dead value, 1 unpopulated, many unreachable states |
| Tables | 46 | ~19 (cookbook/commerce/content) | 3 fully orphaned; ~24 identity/market/finance unwired; 5 never populated |
| RPCs (callable) | ~29 | **6** | **~23** |
| Routes (pages+api) | ~45 | all render | see P2 placeholders |
| Components | 8 | **8 (0 dead)** | — |
| lib resolvers | — | most | authz.ts (whole module), 3 fns |

Full per-item detail lives in the cycle-001 analysis (this file's §2). Regenerate each cycle.

---

## 4. Ghost-flow trace (static — no live DB)

| # | Ghost account | UI entry point | Flow | Verdict |
|---|---------------|----------------|------|---------|
| 1 | **Visitor (anon)** | `/`, `/cookbook` | early-access → `/api/leads` → `create_cookbook_lead` ✅; pre-order → `/api/checkout/create` → Stripe → webhook writes order ✅ | **Works.** But payment never hits ledger/audit (P0-2); success page unverified (P2). |
| 2 | **Customer (magic-link)** | `/login` | callback → `claim_my_purchases` + `accept_pending_invites` → `/account` → orders + downloads → `redeem_download` ✅ | **Works.** No wallet/points UI though read RPCs exist (P1); PDF gate deferred (P2). |
| 3 | **Admin (allowlist)** | `/login` + `ADMIN_EMAILS` | `/admin` CMS: recipe/ingredient/meal-plan/blog CRUD ✅ | **Works, mostly.** Can't create meal plans via UI (P2); gate ignores DB RBAC (P0-4); no audit trail on writes. |
| 4 | **platform_admin / operations / finance / support** | — | — | **Dead-end at step 0.** No route, no resolver, no onboarding UI. RPCs orphaned. |
| 5 | **merchant_admin / manager / picker** | — | — | **Dead-end at step 0.** No merchant portal exists. |
| 6 | **driver** | — | — | **Dead-end at step 0.** No driver surface exists. |
| 7 | **Farmers Market customer** | — | — | **No storefront.** `/market*` routes do not exist; `market_orders` has no write path. |

**Takeaway:** every authenticated surface beyond customer + allowlist-admin is unreachable. The
product today is a cookbook shop with a CMS; the platform/marketplace is backend-only.

---

## 5. Cross-reference: open PRs

**None open** at cycle 001. Nothing to reconcile against these findings. Historical waves (1A–1C.1)
are all merged into trunk. **Wave 1D (Notifications)** is documented as "awaits review, not started"
— consistent with `notification_outbox` having rows enqueued but no dispatcher.

---

## 6. Recommended next moves (not yet actioned — awaiting direction)

Priority order, smallest-blast-radius first:

1. **Confirm the deploy target** (blocks everything live): which Supabase project is NutriEat's, or
   create one, so migrations can be applied and ghost flows actually run. Resolve the
   ciri-os / nutrieat / CIRI naming mismatch.
2. **Wire the money path to the ledger + audit** (P0-2): have the Stripe webhook call
   `post_financial_journal` (12% commission split) and `record_audit_event` on paid orders. Closes
   the biggest correctness gap and lights up the ledger's zero read-RPCs.
3. **Decide the fate of the unwired backend** (P0-1/3): either (a) build the thin resolver+route
   layer for staff/merchant/market, or (b) explicitly park it behind a feature flag / doc note so it
   reads as "staged," not "dead." Right now it reads as dead.
4. **Migrate admin gate to DB roles** (P0-4): swap `ADMIN_EMAILS` for `current_platform_role()` to
   honour ADR-0009; keep the allowlist only as the super-admin bootstrap.
5. **Housekeeping:** add `/admin/meal-plans/new`; wire `/survey` to `/api/surveys` or delete the
   endpoint; delete 15 stale `wave-*` branches; drop or clearly park the 3 orphan tables and the
   dead `get_public_recipe` RPC / `lib/authz.ts` module.

---

*Cycle 001 baseline. Next cycle: diff trunk against this SHA, re-run the three layer inventories,
re-trace the ghost table, and reconcile against any open PRs.*
