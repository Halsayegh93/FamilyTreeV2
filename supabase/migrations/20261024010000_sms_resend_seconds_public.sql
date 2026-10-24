-- عدّاد «إعادة عبر SMS» في شاشة الدخول يقرأ «بين رمز ورمز» من الإعدادات (طلب المالك ٢٠٢٦-١٠-٢٤:
-- «اذا العداد يقرا الرقم من الاعدادات بس حددلي مكان التعديل»). رقم واحد فقط قبل الدخول — لا يكشف شيئاً آخر.
-- نفس حدود السيرفر: sms_one_code_seconds (افتراضياً ٣٠٠) ولا يقل عن sms_wait_seconds في app_settings.
-- مطبَّق على الحي ٢٠٢٦-١٠-٢٤ (ومعه sms_one_code_seconds = 180 بطلب المالك «بعد ٣ دقايق»). التراجع: drop function.
create or replace function public.sms_resend_seconds() returns int
language sql stable security definer set search_path = '' as $$
  select greatest(
    coalesce(public.config_int('sms_one_code_seconds', 300), 0),
    coalesce((select a.sms_wait_seconds from public.app_settings a order by a.updated_at desc limit 1), 60));
$$;
revoke all on function public.sms_resend_seconds() from public;
grant execute on function public.sms_resend_seconds() to anon, authenticated;
