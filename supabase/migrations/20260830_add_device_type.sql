-- أضف نوع الجهاز للسجلات الحالية والجديدة.
alter table public.assets
  add column if not exists device_type text not null default 'other';

create index if not exists assets_user_device_type_idx
  on public.assets (user_id, device_type, scanned_at desc);

-- صنّف السجلات القديمة المعروفة من اسم الموديل، واترك غير المعروف تحت "أخرى".
update public.assets set device_type = case
  when lower(model) ~ 'monitor|display|شاشة' then 'monitor'
  when lower(model) ~ 'scanner|ds-410|سكانر' then 'scanner'
  when lower(model) ~ 'printer|mfp|laserjet|tm-t88|طابعة' then 'printer'
  when lower(model) ~ 'cisco|phone|هاتف' then 'cisco_phone'
  when lower(model) ~ 'z2|elitedesk|prodesk|optiplex|desktop|(^|[^a-z])pc([^a-z]|$)' then 'pc'
  else 'other'
end
where device_type = 'other';
