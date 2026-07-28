-- NutriEat Platform — Wave 1C.1 (PR A): chart-of-accounts extensions
-- ADDITIVE ONLY. Migration 0017 is frozen and unchanged. This migration only ADDS enum labels to
-- financial_account_kind so the customer-credit classifications and the platform operational-expense
-- account are independently calculable in the SAME double-entry ledger (no side tables, no reward_ledger).
--
-- Kept as its OWN migration (separate transaction) on purpose: Postgres forbids USING a newly added
-- enum label in the same transaction that adds it. Splitting the ADD VALUE here (committed first) from
-- the operations in 0019 keeps a fresh-DB migration run correct. No functions/data use the new labels here.
--
-- New customer-credit liability kinds — one per classification, so each balance is derivable purely from
-- postings on its own account kind (the "separate account kinds" option from the brief):
--   customer_general_credit_liability      — goodwill / gift / manual general credit
--   customer_refund_credit_liability       — store-credit issued in lieu of a cash refund
--   customer_promotional_credit_liability  — marketing / promotional credit
-- referral_cashback keeps the EXISTING 0017 kind customer_cashback_liability (already distinct), so
-- cashback stays separately queryable from every credit class and from points.
--
-- New expense kind:
--   platform_operating_expense — platform-absorbed operational loss / cost (funds promotional credit &
--   cashback; absorbs platform-liability losses). Distinct from stripe_fee_expense (processor cost).

alter type financial_account_kind add value if not exists 'customer_general_credit_liability';
alter type financial_account_kind add value if not exists 'customer_refund_credit_liability';
alter type financial_account_kind add value if not exists 'customer_promotional_credit_liability';
alter type financial_account_kind add value if not exists 'platform_operating_expense';
