-- مطابقة الأرقام بالرقم الكامل مع مفتاح الدولة — 2026-09-28
--
-- المشكلة: phones_match_suffix كانت تقارن آخر ٨ أرقام فقط وتتجاهل مفتاح الدولة.
-- handle_new_user_by_phone يشتغل عند إنشاء حساب الدخول (أي عند طلب الرمز،
-- قبل التحقق)، فطلب رمز لـ +973XXXXXXXX نقل ملف عضو رقمه +965XXXXXXXX كاملاً
-- إلى حساب دخول جديد غير متحقَّق منه، وصار صاحب الرقم الكويتي بلا ملف.
-- حصل فعلاً لحساب المالك (2026-09-27 20:17).
--
-- الحل: نفس الاسم (يُصلح كل المستدعين: find_profile_id_by_auth_phone،
-- trg_profiles_link_auth_on_phone_set، freeze_member_on_ban،
-- reject_banned_phone_registration) لكن المقارنة بالرقم الكامل:
-- أرقام فقط، حذف 00 الدولية، و٨ أرقام محلية = كويتي (+965).

begin;

create or replace function public.phones_match_suffix(a text, b text)
returns boolean
language sql
immutable
set search_path to 'public'
as $$
  with d as (
    select regexp_replace(regexp_replace(coalesce(a, ''), '[^0-9]', '', 'g'), '^00', '') as da,
           regexp_replace(regexp_replace(coalesce(b, ''), '[^0-9]', '', 'g'), '^00', '') as db
  ), c as (
    select case when length(da) = 8 then '965' || da else da end as ca,
           case when length(db) = 8 then '965' || db else db end as cb
    from d
  )
  select length(ca) >= 8 and length(cb) >= 8 and ca = cb from c;
$$;

commit;
