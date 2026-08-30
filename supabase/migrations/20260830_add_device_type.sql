-- أضف نوع الجهاز للسجلات الحالية والجديدة.
alter table public.assets
  add column if not exists device_type text not null default 'other';

create index if not exists assets_user_device_type_idx
  on public.assets (user_id, device_type, scanned_at desc);

