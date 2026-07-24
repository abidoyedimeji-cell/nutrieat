-- NutriEat — accounts + digital delivery
-- Bridges guest checkout to logged-in accounts, and gates PDF downloads behind ownership,
-- launch-day availability, and the download limit. Additive only.

-- Attach guest orders/entitlements (made with the same email) to the logged-in account.
create or replace function claim_my_purchases()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_email text := auth.email();
begin
  if v_uid is null or v_email is null then
    return;
  end if;
  update orders
     set user_id = v_uid
   where user_id is null and lower(customer_email) = lower(v_email);
  update download_entitlements
     set user_id = v_uid
   where user_id is null and lower(customer_email) = lower(v_email);
end;
$$;
revoke all on function claim_my_purchases() from public;
grant execute on function claim_my_purchases() to authenticated;

-- Redeem a download: validates ownership + launch-day gate + limit, increments the count,
-- returns the storage path so the server can mint a signed URL. Locked while available_at
-- is null or in the future.
create or replace function redeem_download(p_entitlement_id uuid)
returns table (file_path text)
language plpgsql
security definer
set search_path = public
as $$
declare
  e download_entitlements%rowtype;
begin
  select * into e from download_entitlements
   where id = p_entitlement_id and user_id = auth.uid();
  if not found then raise exception 'not_found'; end if;
  if not e.active then raise exception 'inactive'; end if;
  if e.available_at is null or now() < e.available_at then raise exception 'not_yet_available'; end if;
  if e.download_count >= e.download_limit then raise exception 'limit_reached'; end if;

  update download_entitlements set download_count = download_count + 1 where id = e.id;
  return query select e.file_path;
end;
$$;
revoke all on function redeem_download(uuid) from public;
grant execute on function redeem_download(uuid) to authenticated;

-- Private bucket for the cookbook PDF — access only via short-lived signed URLs.
insert into storage.buckets (id, name, public)
values ('cookbook-pdf', 'cookbook-pdf', false)
on conflict (id) do nothing;
