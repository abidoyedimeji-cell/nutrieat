-- NutriEat — harden table grants
-- RLS already protects rows, but by default anon/authenticated hold table grants (so the
-- tables appear in the auto REST/GraphQL API). Revoke those grants on private tables so
-- they aren't reachable at all by public roles. SECURITY DEFINER RPCs (owned by the
-- migration role) and the service-role key bypass grants, so writes/reads still work.

-- Fully private: no RLS policies; reached only via RPCs + service-role.
revoke all on table cookbook_leads   from anon, authenticated;
revoke all on table survey_responses from anon, authenticated;
revoke all on table payment_events   from anon, authenticated;

-- Owner-scoped: authenticated reads own rows (Phase 6) via RLS; anon never touches them.
revoke all on table orders                from anon;
revoke all on table order_items           from anon;
revoke all on table download_entitlements from anon;
revoke all on table profiles              from anon;
