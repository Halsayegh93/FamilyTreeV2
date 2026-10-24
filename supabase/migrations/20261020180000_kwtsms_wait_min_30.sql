-- طلب المالك ٢٠٢٦-١٠-٢٠ («نعم سوه» — وقت انتظار أقل من دقيقة): حد Supabase نفسه بين رمزين لنفس الرقم
-- sms_max_frequency = ٥ ثوانٍ (قُرئ من إعدادات Auth)، فالحد الأدنى للانتظار في التطبيق ينزل من ٦٠ إلى ٣٠ ثانية.
-- مهلة الحجز الداخلية = الانتظار - ١٠ ث (٢٠ ث عند ٣٠) — أعلى من حد Supabase، فلا تصادم.
-- التراجع: supabase/rollback/20261020180000_kwtsms_wait_min_30_rollback.sql
alter table public.app_settings drop constraint app_settings_sms_wait_seconds_check;
alter table public.app_settings add constraint app_settings_sms_wait_seconds_check
  check (sms_wait_seconds between 30 and 600);
