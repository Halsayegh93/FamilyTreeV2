-- العرض members_masked يعمل بصلاحية مالكه (ليس security_invoker) فيتجاوز RLS
-- على profiles — أي أن شرط WHERE داخله هو الحماية الوحيدة. وكان يقبل الدور
-- 'member' بلا نظر للحالة، و1649 حساباً «قيد الموافقة» دورها member، فكانت
-- تقرأ الشجرة كاملة عبره رغم إغلاق الجدول عليها.
create or replace view public.members_masked as
select id, first_name, full_name,
       case when coalesce(is_phone_hidden,false) = false or id = auth.uid() or is_team(auth.uid())
            then phone_number else null::text end as phone_number,
       birth_date, death_date, is_deceased, role, father_id, photo_url,
       is_phone_hidden, is_hidden_from_tree, sort_order, bio_json, sons_ids, status,
       created_at, is_married, avatar_url, bio, is_approved, is_admin,
       is_phone_verified, is_birth_date_hidden, cover_url, badge_enabled, gender,
       updated_by, updated_at, is_hr_member, hr_status, last_seen_at,
       registration_platform, username, last_active_at, current_screen,
       current_screen_source,
       case when id = auth.uid() or is_team(auth.uid()) then email else null::text end as email,
       mother_id, husband_id, terms_accepted_at, family_name,
       death_date_unknown, avatar_unavailable
from public.profiles p
where auth.uid() is not null
  and (id = auth.uid() or public.is_approved_member());
