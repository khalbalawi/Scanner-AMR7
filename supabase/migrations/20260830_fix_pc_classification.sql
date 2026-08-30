-- تصحيح تصنيف موديلات الكمبيوتر المكتوبة بمسافات مثل HP Z 2 وHP ELITE DESK.
update public.assets
set device_type = 'pc'
where device_type = 'other'
  and lower(model) ~ 'z[[:space:]]*2|elite[[:space:]]*desk|pro[[:space:]]*desk|opti[[:space:]]*plex|desktop|workstation|(^|[^a-z])pc([^a-z]|$)';
