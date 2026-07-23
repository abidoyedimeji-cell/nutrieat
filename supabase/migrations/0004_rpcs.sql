-- NutriEat — RPCs (public write surface + safe reads)
-- Public functions are SECURITY DEFINER with a pinned search_path and execute granted
-- to anon + authenticated. Commerce RPCs (create_pending_order, confirm_paid_order,
-- redeem_download) arrive with the commerce sprint since they need Stripe context.

-- ---------------------------------------------------------- create_cookbook_lead
create or replace function create_cookbook_lead(
  p_email             text,
  p_full_name         text default null,
  p_source            lead_source default 'early_access',
  p_marketing_consent boolean default true,
  p_preferred_format  text default null,
  p_utm_source        text default null,
  p_utm_medium        text default null,
  p_utm_campaign      text default null,
  p_utm_content       text default null,
  p_utm_term          text default null,
  p_landing_page      text default null,
  p_referrer          text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if p_email is null or position('@' in p_email) = 0 then
    raise exception 'invalid email';
  end if;

  insert into cookbook_leads (
    email, full_name, source, marketing_consent, preferred_format,
    utm_source, utm_medium, utm_campaign, utm_content, utm_term, landing_page, referrer
  )
  values (
    lower(trim(p_email)), p_full_name, p_source, p_marketing_consent, p_preferred_format,
    p_utm_source, p_utm_medium, p_utm_campaign, p_utm_content, p_utm_term, p_landing_page, p_referrer
  )
  on conflict (email) do update
    set marketing_consent = excluded.marketing_consent,
        full_name         = coalesce(excluded.full_name, cookbook_leads.full_name),
        preferred_format  = coalesce(excluded.preferred_format, cookbook_leads.preferred_format)
  returning id into v_id;

  return v_id;
end;
$$;

-- ---------------------------------------------------------- submit_cookbook_survey
create or replace function submit_cookbook_survey(
  p_email                     text,
  p_reason_for_joining        text default null,
  p_relationship_with_food    text default null,
  p_desired_change            text default null,
  p_priority_areas            text[] default null,
  p_food_choice_influences    text default null,
  p_premium_value_expectation text default null,
  p_involvement_level         text default null,
  p_future_vision             text default null,
  p_trust_driver              text default null,
  p_open_ideas                text default null,
  p_raw                       jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lead_id     uuid;
  v_response_id uuid;
  v_email       text := lower(trim(p_email));
begin
  if v_email is null or position('@' in v_email) = 0 then
    raise exception 'invalid email';
  end if;

  select id into v_lead_id from cookbook_leads where email = v_email;
  if v_lead_id is null then
    insert into cookbook_leads (email, source) values (v_email, 'survey')
    returning id into v_lead_id;
  end if;

  update cookbook_leads set completed_survey = true where id = v_lead_id;

  insert into survey_responses (
    lead_id, email, reason_for_joining, relationship_with_food, desired_change,
    priority_areas, food_choice_influences, premium_value_expectation, involvement_level,
    future_vision, trust_driver, open_ideas, raw
  )
  values (
    v_lead_id, v_email, p_reason_for_joining, p_relationship_with_food, p_desired_change,
    p_priority_areas, p_food_choice_influences, p_premium_value_expectation, p_involvement_level,
    p_future_vision, p_trust_driver, p_open_ideas, p_raw
  )
  returning id into v_response_id;

  return v_response_id;
end;
$$;

-- ---------------------------------------------------------- get_public_recipe (safe read)
create or replace function get_public_recipe(p_slug text)
returns setof recipes
language sql
security definer
set search_path = public
as $$
  select * from recipes
  where slug = p_slug
    and content_status = 'published'
    and visibility = 'public_preview';
$$;

-- grants: only the intended public surface
revoke all on function create_cookbook_lead(text, text, lead_source, boolean, text, text, text, text, text, text, text, text) from public;
grant execute on function create_cookbook_lead(text, text, lead_source, boolean, text, text, text, text, text, text, text, text) to anon, authenticated;

revoke all on function submit_cookbook_survey(text, text, text, text, text[], text, text, text, text, text, text, jsonb) from public;
grant execute on function submit_cookbook_survey(text, text, text, text, text[], text, text, text, text, text, text, jsonb) to anon, authenticated;

grant execute on function get_public_recipe(text) to anon, authenticated;
