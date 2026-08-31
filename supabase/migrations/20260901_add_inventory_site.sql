-- يحفظ موقع الجرد مع كل جهاز دون التأثير على السجلات السابقة.
alter table public.assets add column if not exists site_type text not null default '';
alter table public.assets add column if not exists site_name text not null default '';

alter table public.assets drop constraint if exists assets_site_type_check;
alter table public.assets add constraint assets_site_type_check
  check (site_type in ('', 'border_crossing', 'airport', 'seaport', 'branch', 'other'));

alter table public.assets drop constraint if exists assets_site_name_check;
alter table public.assets add constraint assets_site_name_check
  check (char_length(site_name) <= 120);
