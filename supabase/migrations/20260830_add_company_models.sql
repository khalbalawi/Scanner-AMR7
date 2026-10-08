-- تصنيف الموديلات الإضافية الموجودة في الشركة.
update public.assets set device_type = 'printer'
where device_type = 'other'
  and lower(model) ~ 'p[[:space:]]*57750[[:space:]]*dw|m[[:space:]]*603';

update public.assets set device_type = 'cisco_phone'
where device_type = 'other'
  and lower(model) ~ 'cisco|ip[[:space:]]*phone|cp[[:space:]-]*7841';

update public.assets set device_type = 'pc'
where device_type = 'other'
  and lower(model) ~ 'z[[:space:]]*2|elite[[:space:]]*one|all[[:space:]-]*in[[:space:]-]*one|workstation';
