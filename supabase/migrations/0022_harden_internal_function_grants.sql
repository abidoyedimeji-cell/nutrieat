-- NutriEat Platform — Wave 1C.1 (PR C): additive internal-function grant hardening
-- Migration 0017 frozen — this only REVOKES default-privilege grants Supabase auto-attached; it does not
-- alter any 0017 object. Verification surfaced three internal functions left browser-executable by earlier
-- migrations (Supabase ALTER DEFAULT PRIVILEGES grants EXECUTE on every new function to PUBLIC/anon/
-- authenticated/service_role):
--   _enqueue_notification       — internal writer (enqueues notifications). Called only by SECURITY
--                                 DEFINER RPCs (invite_merchant_staff, _grant_or_invite_platform), which
--                                 keep working — they execute as the owner, not the caller.
--   _financial_assert_balanced  — 0017 deferred balance constraint trigger fn.
--   _financial_block_mutation   — 0017 append-only immutability trigger fn.
-- Revoking EXECUTE does NOT stop a trigger function from firing (Postgres does not check EXECUTE for
-- trigger invocation), so this is safe defence-in-depth. After this, the automated internal-function
-- guard (wave1c1_verification.sql) returns zero rows.
revoke all on function _enqueue_notification(text, text, uuid, jsonb) from public, anon, authenticated;
revoke all on function _financial_assert_balanced() from public, anon, authenticated;
revoke all on function _financial_block_mutation() from public, anon, authenticated;
