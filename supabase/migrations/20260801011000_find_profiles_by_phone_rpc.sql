-- مطابقة الهاتف على السيرفر بدل سحب الأرقام للعميل — 2026-08-01
--
-- المشكلة الحالية: مسار تسجيل الدخول يجلب حتى ٥٠٠ رقم هاتف إلى الجهاز
-- ليطابقها محلياً (AuthViewModel.findProfileByPhone). هذا تسريب بحد ذاته،
-- وسيتعطّل أصلاً بعد منع عمود phone_number عن authenticated.
--
-- البديل: دالة SECURITY DEFINER تطابق آخر ٨ أرقام على السيرفر وتُرجع
-- المعرّف والدور والحالة فقط — بلا أي رقم هاتف.
--
-- إضافية فقط — لا تكسر أي نسخة تطبيق منشورة.

begin;

create or replace function public.find_profiles_by_phone(p_phone text)
returns table (id uuid, role text, status text)
language sql
stable
security definer
set search_path = public
as $$
  with target as (
    select right(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'), 8) as last8
  )
  select p.id, p.role, p.status
  from public.profiles p, target t
  where length(t.last8) = 8
    and right(regexp_replace(coalesce(p.phone_number, ''), '\D', '', 'g'), 8) = t.last8
  limit 20;
$$;

revoke all on function public.find_profiles_by_phone(text) from public;
grant execute on function public.find_profiles_by_phone(text) to anon, authenticated;

commit;
