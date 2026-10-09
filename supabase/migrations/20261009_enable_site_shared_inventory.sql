-- اجعل كل حساب يرى السجل الموحد لموقعه بدل تقسيم الأجهزة حسب المستخدم.

begin;

create or replace function public.can_access_inventory_site(
  p_site_type text,
  p_site_name text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.user_profiles profile
    where profile.user_id = (select auth.uid())
      and (
        profile.role = 'admin'
        or (
          profile.site_type = p_site_type
          and profile.site_name = p_site_name
        )
      )
  );
$$;

revoke all on function public.can_access_inventory_site(text, text) from public;
grant execute on function public.can_access_inventory_site(text, text) to authenticated;

drop policy if exists "assets_select_own" on public.assets;
drop policy if exists "assets_insert_own" on public.assets;
drop policy if exists "assets_update_own" on public.assets;
drop policy if exists "assets_delete_own" on public.assets;
drop policy if exists assets_select_site on public.assets;
drop policy if exists assets_insert_site on public.assets;
drop policy if exists assets_update_site on public.assets;
drop policy if exists assets_delete_site on public.assets;

create policy assets_select_site on public.assets
for select to authenticated
using (public.can_access_inventory_site(site_type, site_name));

create policy assets_insert_site on public.assets
for insert to authenticated
with check (
  user_id = (select auth.uid())
  and public.can_access_inventory_site(site_type, site_name)
);

create policy assets_update_site on public.assets
for update to authenticated
using (public.can_access_inventory_site(site_type, site_name))
with check (public.can_access_inventory_site(site_type, site_name));

create policy assets_delete_site on public.assets
for delete to authenticated
using (public.can_access_inventory_site(site_type, site_name));

-- يمنع تسجيل الرقم التسلسلي نفسه مرتين داخل الموقع حتى لو استخدم موظفان حسابين مختلفين.
create unique index if not exists assets_site_serial_unique_idx
  on public.assets (site_type, site_name, upper(trim(serial)));

drop policy if exists "return_shipments_select_own" on public.return_shipments;
drop policy if exists "return_shipments_insert_own" on public.return_shipments;
drop policy if exists return_shipments_select_site on public.return_shipments;
drop policy if exists return_shipments_insert_site on public.return_shipments;

create policy return_shipments_select_site on public.return_shipments
for select to authenticated
using (public.can_access_inventory_site(from_site_type, from_site_name));

create policy return_shipments_insert_site on public.return_shipments
for insert to authenticated
with check (
  user_id = (select auth.uid())
  and public.can_access_inventory_site(from_site_type, from_site_name)
);

drop policy if exists "return_shipment_items_select_own" on public.return_shipment_items;
drop policy if exists "return_shipment_items_insert_own" on public.return_shipment_items;
drop policy if exists return_shipment_items_select_site on public.return_shipment_items;
drop policy if exists return_shipment_items_insert_site on public.return_shipment_items;

create policy return_shipment_items_select_site on public.return_shipment_items
for select to authenticated
using (
  exists (
    select 1
    from public.return_shipments shipment
    where shipment.id = shipment_id
      and public.can_access_inventory_site(shipment.from_site_type, shipment.from_site_name)
  )
);

create policy return_shipment_items_insert_site on public.return_shipment_items
for insert to authenticated
with check (user_id = (select auth.uid()));

create or replace function public.return_assets_to_it_store(
  p_asset_ids uuid[],
  p_waybill_number text,
  p_notes text default '',
  p_site_type text default '',
  p_site_name text default ''
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_shipment_id uuid;
  v_asset_count integer;
begin
  if coalesce(cardinality(p_asset_ids), 0) = 0 then
    raise exception 'Select at least one asset';
  end if;
  if nullif(trim(p_waybill_number), '') is null then
    raise exception 'Waybill number is required';
  end if;
  if not public.can_access_inventory_site(p_site_type, trim(p_site_name)) then
    raise exception 'The selected site is not assigned to this account';
  end if;

  perform 1
  from public.assets
  where id = any(p_asset_ids)
    and custody_state = 'active'
    and site_type = p_site_type
    and site_name = trim(p_site_name)
  order by id
  for update;

  select count(*) into v_asset_count
  from public.assets
  where id = any(p_asset_ids)
    and custody_state = 'active'
    and site_type = p_site_type
    and site_name = trim(p_site_name);

  if v_asset_count <> cardinality(p_asset_ids) then
    raise exception 'One or more assets are unavailable or already returned';
  end if;

  insert into public.return_shipments (
    user_id, waybill_number, from_site_type, from_site_name, notes
  ) values (
    (select auth.uid()), trim(p_waybill_number), p_site_type, trim(p_site_name), coalesce(trim(p_notes), '')
  ) returning id into v_shipment_id;

  insert into public.return_shipment_items (
    shipment_id, asset_id, user_id, serial, asset_number, device_type, model, status
  )
  select
    v_shipment_id,
    id,
    (select auth.uid()),
    serial,
    asset_number,
    device_type,
    model,
    status
  from public.assets
  where id = any(p_asset_ids)
    and custody_state = 'active'
    and site_type = p_site_type
    and site_name = trim(p_site_name);

  update public.assets
  set custody_state = 'returned',
      returned_at = now(),
      return_shipment_id = v_shipment_id
  where id = any(p_asset_ids)
    and custody_state = 'active'
    and site_type = p_site_type
    and site_name = trim(p_site_name);

  return v_shipment_id;
end;
$$;

grant execute on function public.return_assets_to_it_store(uuid[], text, text, text, text) to authenticated;

commit;
