-- يحدّد إن كان المستخدم من فريق الإدارة (يرى الأرقام المخفية).
create or replace function public.is_team(uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1 from public.profiles p
    where p.id = uid
      and (coalesce(p.is_admin, false) = true
           or lower(coalesce(p.role, '')) in ('owner','admin','monitor','supervisor'))
  );
$$;

-- عرض الأعضاء مع إخفاء رقم الهاتف على مستوى السيرفر:
-- يظهر الرقم فقط إذا: عام (is_phone_hidden=false) أو لصاحبه أو لفريق الإدارة.
-- يُستخدم لجلب قائمة الشجرة بدل قراءة جدول profiles مباشرة.
create or replace view public.members_masked
with (security_invoker = on)
as
select
  id, first_name, full_name,
  case
    when coalesce(is_phone_hidden, false) = false
      or id = auth.uid()
      or public.is_team(auth.uid())
    then phone_number
    else null
  end as phone_number,
  birth_date, death_date, is_deceased, role, father_id, photo_url,
  is_phone_hidden, is_hidden_from_tree, sort_order, bio_json, sons_ids,
  status, created_at, is_married, avatar_url, bio, is_approved, is_admin,
  is_phone_verified, is_birth_date_hidden, cover_url, badge_enabled, gender,
  updated_by, updated_at, is_hr_member, hr_status, last_seen_at,
  registration_platform, username, last_active_at, current_screen,
  current_screen_source, email, mother_id, husband_id, terms_accepted_at
from public.profiles;

grant select on public.members_masked to anon, authenticated;;
