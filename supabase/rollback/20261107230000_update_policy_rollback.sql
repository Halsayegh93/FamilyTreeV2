-- تراجع 20261107230000_update_policy: يحذف الدوال والمفاتيح وأعمدة النسخة على الأجهزة.
-- التطبيق يرجع للطريقة السابقة تلقائياً (`app_update_policy` غير موجودة ← القفل بـ app_settings.ios_min_build فقط،
-- و`report_app_build` يفشل بصمت). app_settings (الحد الأدنى والروابط والطريقة القديمة للأندرويد) لا تُلمس.
drop function if exists public.app_build_overview(integer);
drop function if exists public.report_app_build(text, integer, text);
drop function if exists public.set_update_policy(jsonb);
drop function if exists public.update_policy_admin();
drop function if exists public.app_update_policy(text, integer);
drop function if exists private.update_policy_texts();
drop function if exists private.update_policy_values(text);

delete from public.app_config
 where key in ('ios_latest_build', 'android_latest_build', 'ios_latest_version', 'android_latest_version',
               'update_mode_ios', 'update_mode_android', 'update_deadline_ios', 'update_deadline_android',
               'update_snooze_days', 'update_whats_new', 'update_force_title', 'update_force_message',
               'update_reminder_title', 'update_reminder_body');

alter table public.device_tokens drop constraint if exists device_tokens_app_build_check;
alter table public.device_tokens drop constraint if exists device_tokens_app_version_check;
alter table public.device_tokens
  drop column if exists app_build,
  drop column if exists app_version,
  drop column if exists build_seen_at;

notify pgrst, 'reload schema';
