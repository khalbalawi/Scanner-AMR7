-- شغّل الملف كاملاً مرة واحدة من Supabase SQL Editor.
-- لا تستخدم service_role داخل تطبيق الويب.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(trim(display_name)) between 2 and 80),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.assets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  serial text not null check (char_length(trim(serial)) between 1 and 200),
  asset_number text not null default '' check (char_length(asset_number) <= 200),
  device_type text not null default 'other' check (device_type in ('monitor', 'pc', 'scanner', 'printer', 'cisco_phone', 'other')),
  model text not null default '' check (char_length(model) <= 200),
  status text not null check (status in ('جديد', 'مستعمل', 'للصيانة', 'تالف')),
  notes text not null default '' check (char_length(notes) <= 1000),
  site_type text not null default '' check (site_type in ('', 'border_crossing', 'airport', 'seaport', 'branch', 'other')),
  site_name text not null default '' check (char_length(site_name) <= 120),
  scanned_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint assets_user_serial_unique unique (user_id, serial)
);

-- ترقية آمنة للمشاريع التي أنشأت جدول assets قبل إضافة نوع الجهاز.
alter table public.assets
  add column if not exists device_type text not null default 'other';

alter table public.assets add column if not exists site_type text not null default '';
alter table public.assets add column if not exists site_name text not null default '';

create index if not exists assets_user_device_type_idx
  on public.assets (user_id, device_type, scanned_at desc);

create index if not exists assets_user_scanned_at_idx
  on public.assets (user_id, scanned_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

drop trigger if exists assets_set_updated_at on public.assets;
create trigger assets_set_updated_at
before update on public.assets
for each row execute function public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''), split_part(new.email, '@', 1))
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.assets enable row level security;

drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own"
on public.profiles for select
to authenticated
using ((select auth.uid()) = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
on public.profiles for update
to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

drop policy if exists "assets_select_own" on public.assets;
create policy "assets_select_own"
on public.assets for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "assets_insert_own" on public.assets;
create policy "assets_insert_own"
on public.assets for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists "assets_update_own" on public.assets;
create policy "assets_update_own"
on public.assets for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists "assets_delete_own" on public.assets;
create policy "assets_delete_own"
on public.assets for delete
to authenticated
using ((select auth.uid()) = user_id);

grant usage on schema public to authenticated;
grant select, update on public.profiles to authenticated;
grant select, insert, update, delete on public.assets to authenticated;
revoke all on public.profiles from anon;
revoke all on public.assets from anon;
