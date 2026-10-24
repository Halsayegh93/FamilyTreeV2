-- تراجع 20261021130000_registration_and_device_guards: يحذف الحراس الثلاثة (التسجيل في profiles وadmin_requests، حد الأجهزة)
-- وقيد ١..١٠ إن كان هذا الترحيل من أضافه (علامة التعليق). لا بيانات تتغيّر. يعمل على قاعدة لم يُطبَّق عليها الترحيل.
drop trigger if exists trg_profiles_registration_gate on public.profiles;
drop trigger if exists trg_admin_requests_registration_gate on public.admin_requests;
drop trigger if exists trg_device_tokens_limit on public.device_tokens;
drop function if exists public.trg_profiles_registration_gate();
drop function if exists public.trg_admin_requests_registration_gate();
drop function if exists public.trg_device_tokens_limit();
do $$
begin
  if exists (select 1 from pg_constraint c
              where c.conname = 'app_settings_max_devices_per_user_check'
                and c.conrelid = 'public.app_settings'::regclass
                and obj_description(c.oid, 'pg_constraint') = 'added by 20261021130000') then
    alter table public.app_settings drop constraint app_settings_max_devices_per_user_check;
  end if;
end $$;
