-- استرجاع الأجهزة من الموقع إلى IT Store مع سجل بوليصات غير قابل للفقد.

create table if not exists public.return_shipments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  waybill_number text not null check (char_length(trim(waybill_number)) between 1 and 120),
  from_site_type text not null default '',
  from_site_name text not null default '' check (char_length(from_site_name) <= 120),
  destination text not null default 'IT Store' check (destination = 'IT Store'),
  notes text not null default '' check (char_length(notes) <= 1000),
  returned_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table public.assets
  add column if not exists custody_state text not null default 'active';
alter table public.assets
  add column if not exists returned_at timestamptz;
alter table public.assets
  add column if not exists return_shipment_id uuid references public.return_shipments(id) on delete set null;

alter table public.assets drop constraint if exists assets_custody_state_check;
alter table public.assets add constraint assets_custody_state_check
  check (custody_state in ('active', 'returned'));

create table if not exists public.return_shipment_items (
  id uuid primary key default gen_random_uuid(),
  shipment_id uuid not null references public.return_shipments(id) on delete cascade,
  asset_id uuid references public.assets(id) on delete set null,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  serial text not null,
  asset_number text not null default '',
  device_type text not null,
  model text not null default '',
  status text not null,
  created_at timestamptz not null default now(),
  constraint return_shipment_items_unique unique (shipment_id, asset_id)
);

create index if not exists assets_user_site_active_idx
  on public.assets (user_id, site_type, site_name, scanned_at desc)
  where custody_state = 'active';
create index if not exists return_shipments_user_site_date_idx
  on public.return_shipments (user_id, from_site_type, from_site_name, returned_at desc);
create index if not exists return_shipment_items_shipment_idx
  on public.return_shipment_items (shipment_id);

alter table public.return_shipments enable row level security;
alter table public.return_shipment_items enable row level security;

-- تبقى لقطة الجهاز في سجل البوليصة حتى لو حُذف أصل الجهاز لاحقاً.
alter table public.return_shipment_items drop constraint if exists return_shipment_items_asset_id_fkey;
alter table public.return_shipment_items alter column asset_id drop not null;
alter table public.return_shipment_items add constraint return_shipment_items_asset_id_fkey
  foreign key (asset_id) references public.assets(id) on delete set null;

drop policy if exists "return_shipments_select_own" on public.return_shipments;
create policy "return_shipments_select_own" on public.return_shipments
for select to authenticated using ((select auth.uid()) = user_id);

drop policy if exists "return_shipments_insert_own" on public.return_shipments;
create policy "return_shipments_insert_own" on public.return_shipments
for insert to authenticated with check ((select auth.uid()) = user_id);

drop policy if exists "return_shipment_items_select_own" on public.return_shipment_items;
create policy "return_shipment_items_select_own" on public.return_shipment_items
for select to authenticated using ((select auth.uid()) = user_id);

drop policy if exists "return_shipment_items_insert_own" on public.return_shipment_items;
create policy "return_shipment_items_insert_own" on public.return_shipment_items
for insert to authenticated with check ((select auth.uid()) = user_id);

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

  perform 1
  from public.assets
  where id = any(p_asset_ids)
    and user_id = (select auth.uid())
  order by id
  for update;

  select count(*) into v_asset_count
  from public.assets
  where id = any(p_asset_ids)
    and user_id = (select auth.uid())
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
  select v_shipment_id, id, user_id, serial, asset_number, device_type, model, status
  from public.assets
  where id = any(p_asset_ids)
    and user_id = (select auth.uid())
    and custody_state = 'active'
    and site_type = p_site_type
    and site_name = trim(p_site_name);

  update public.assets
  set custody_state = 'returned', returned_at = now(), return_shipment_id = v_shipment_id
  where id = any(p_asset_ids)
    and user_id = (select auth.uid())
    and custody_state = 'active'
    and site_type = p_site_type
    and site_name = trim(p_site_name);

  return v_shipment_id;
end;
$$;

grant select, insert on public.return_shipments to authenticated;
grant select, insert on public.return_shipment_items to authenticated;
grant execute on function public.return_assets_to_it_store(uuid[], text, text, text, text) to authenticated;
revoke all on public.return_shipments from anon;
revoke all on public.return_shipment_items from anon;
