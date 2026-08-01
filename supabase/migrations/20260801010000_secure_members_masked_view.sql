-- إعداد مسار الهاتف/الإيميل المشروع قبل منع الأعمدة على profiles — 2026-08-01
--
-- الخلفية: أي عضو مسجّل يقرأ حالياً كل أرقام الهواتف والإيميلات من public.profiles
-- مباشرة، فتفضيل «إخفاء رقمي» (is_phone_hidden) غير مفروض على السيرفر.
--
-- هذه الهجرة **إضافية فقط** — لا تمنع شيئاً ولا تكسر أي نسخة تطبيق منشورة.
-- المنع الفعلي (revoke) يأتي في هجرة لاحقة بعد اعتماد نسخة التطبيق الجديدة.
--
-- members_masked تصبح security_invoker = off (تعمل بصلاحيات المالك) حتى تبقى
-- قادرة على قراءة العمودين بعد منعهما عن authenticated. ولأن ذلك يتجاوز RLS،
-- أُضيف حارس صفوف داخلي يطابق سياسة profiles_select_self_or_active.
--
-- ملاحظة: تُحفظ أسماء الأعمدة وترتيبها كما في الـview السابق (شرط CREATE OR REPLACE)،
-- مع إلحاق family_name في النهاية فقط.

begin;

create or replace view public.members_masked
with (security_invoker = off)
as
select
  p.id, p.first_name, p.full_name,
  -- الهاتف: عام، أو لصاحبه، أو لفريق الإدارة
  case
    when coalesce(p.is_phone_hidden, false) = false
      or p.id = auth.uid()
      or public.is_team(auth.uid())
    then p.phone_number
    else null
  end as phone_number,
  p.birth_date, p.death_date, p.is_deceased, p.role, p.father_id, p.photo_url,
  p.is_phone_hidden, p.is_hidden_from_tree, p.sort_order, p.bio_json, p.sons_ids,
  p.status, p.created_at, p.is_married, p.avatar_url, p.bio, p.is_approved, p.is_admin,
  p.is_phone_verified, p.is_birth_date_hidden, p.cover_url, p.badge_enabled, p.gender,
  p.updated_by, p.updated_at, p.is_hr_member, p.hr_status, p.last_seen_at,
  p.registration_platform, p.username, p.last_active_at, p.current_screen,
  p.current_screen_source,
  -- الإيميل: لصاحبه ولفريق الإدارة فقط
  case
    when p.id = auth.uid() or public.is_team(auth.uid())
    then p.email
    else null
  end as email,
  p.mother_id, p.husband_id, p.terms_accepted_at,
  p.family_name
from public.profiles p
-- حارس الصفوف — يعوّض تجاوز RLS الناتج عن security_invoker = off
where auth.uid() is not null
  and (
    p.id = auth.uid()
    or public.current_user_role() in ('member', 'supervisor', 'monitor', 'admin', 'owner')
  );

revoke all on public.members_masked from anon;
grant select on public.members_masked to authenticated;

commit;
