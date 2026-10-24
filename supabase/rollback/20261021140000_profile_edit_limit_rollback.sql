-- تراجع 20261021140000_profile_edit_limit: يحذف المحفّز والدوال الأربع وجدول العدّادات (العدّادات تُفقد — التطبيقات
-- ترجع لعدّاد الجهاز، وأي نسخة تقرأ profile_edit_limits تأخذ خطأ «غير موجودة» فتعود لعدّادها المحلي كما في SPEC.md).
-- طبّقه قبل تراجع 20261021110000_app_config. يعمل على قاعدة لم يُطبَّق عليها الترحيل.
drop trigger if exists trg_profiles_self_edit_limit on public.profiles;
drop function if exists public.trg_profiles_self_edit_limit();
drop function if exists public.reset_profile_edit_counts(uuid, text);
drop function if exists public.profile_edit_limits(uuid);
drop function if exists public.profile_edit_limit_consume(uuid, text[]);
drop table if exists public.profile_edit_counts;
