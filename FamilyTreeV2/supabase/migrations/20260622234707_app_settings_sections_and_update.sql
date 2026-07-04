-- مفاتيح أقسام جديدة (server-driven) + معلومات التحديث.
alter table public.app_settings
  add column if not exists women_tree_enabled boolean not null default true,
  add column if not exists latest_build integer not null default 0,
  add column if not exists update_message text,
  add column if not exists force_update boolean not null default false,
  add column if not exists update_url text;

comment on column public.app_settings.women_tree_enabled is 'إظهار قسم شجرة العائلة (النساء) — يتحكم به المدير';
comment on column public.app_settings.latest_build is 'أحدث رقم بناء متوفّر — لو أكبر من بناء التطبيق يظهر بانر تحديث';
comment on column public.app_settings.update_message is 'نص رسالة التحديث المعروضة في البانر';
comment on column public.app_settings.force_update is 'تحديث إجباري — يوقف الاستخدام حتى التحديث';
comment on column public.app_settings.update_url is 'رابط التحديث (App Store / متجر) — اختياري';;
