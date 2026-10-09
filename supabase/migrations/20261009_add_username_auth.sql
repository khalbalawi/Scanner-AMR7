-- Username-only access for the inventory app. Supabase Auth keeps an internal
-- email identity, while staff see and use only their username.

begin;

alter table public.user_profiles
  add column if not exists username text,
  add column if not exists username_key text;

with candidates as (
  select
    profile.user_id,
    coalesce(nullif(lower(trim(split_part(profile.email, '@', 1))), ''), 'user-' || left(profile.user_id::text, 8)) as base_username,
    row_number() over (
      partition by coalesce(nullif(lower(trim(split_part(profile.email, '@', 1))), ''), 'user-' || left(profile.user_id::text, 8))
      order by profile.created_at, profile.user_id
    ) as duplicate_number
  from public.user_profiles profile
  where profile.username is null or profile.username_key is null
)
update public.user_profiles profile
set username = case
      when candidate.duplicate_number = 1 then candidate.base_username
      else candidate.base_username || '-' || left(profile.user_id::text, 6)
    end,
    username_key = case
      when candidate.duplicate_number = 1 then candidate.base_username
      else candidate.base_username || '-' || left(profile.user_id::text, 6)
    end,
    updated_at = now()
from candidates candidate
where profile.user_id = candidate.user_id;

create unique index if not exists user_profiles_username_key_unique
  on public.user_profiles (username_key)
  where username_key is not null;

alter table public.user_profiles drop constraint if exists user_profiles_username_length_check;
alter table public.user_profiles add constraint user_profiles_username_length_check
  check (username is null or char_length(trim(username)) between 3 and 64);

alter table public.user_profiles drop constraint if exists user_profiles_username_key_normalized_check;
alter table public.user_profiles add constraint user_profiles_username_key_normalized_check
  check (username_key is null or username_key = lower(trim(username_key)));

create or replace function public.handle_inventory_user_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  metadata_username text;
begin
  if new.email is null then
    return new;
  end if;

  metadata_username := nullif(trim(new.raw_user_meta_data ->> 'username'), '');

  insert into public.user_profiles (
    user_id,
    email,
    username,
    username_key,
    display_name,
    role
  ) values (
    new.id,
    lower(new.email),
    metadata_username,
    case when metadata_username is null then null else lower(metadata_username) end,
    coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''), metadata_username, split_part(new.email, '@', 1), ''),
    case when exists (
      select 1 from public.app_admin_emails admin_email
      where admin_email.email = lower(new.email)
    ) then 'admin' else 'user' end
  )
  on conflict (user_id) do update
  set email = excluded.email,
      username = coalesce(excluded.username, public.user_profiles.username),
      username_key = coalesce(excluded.username_key, public.user_profiles.username_key),
      display_name = case
        when excluded.display_name = '' then public.user_profiles.display_name
        else excluded.display_name
      end,
      role = case
        when public.user_profiles.role = 'admin' then 'admin'
        else excluded.role
      end,
      updated_at = now();
  return new;
end;
$$;

grant select on public.user_profiles to authenticated;
grant select, insert, update, delete on public.user_profiles to service_role;

commit;
