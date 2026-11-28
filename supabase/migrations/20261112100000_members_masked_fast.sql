-- «أسرع في جلب البيانات» (طلب المالك ٢٠٢٦-١١-١٢) — واجهة `members_masked` أسرع ~٤٠ مرة بنفس النتيجة حرفياً.
--
-- كانت كل خانة مخفية تستدعي `is_team(auth.uid())` و`current_profile_id()` لكل صفّ، والشرط يستدعي `is_approved_member()`
-- لكل صفّ — دوال SECURITY DEFINER بـ search_path فلا تُدمج في الاستعلام: ~٩ استدعاءات × ٣٠٠٠ عضو في كل جلب
-- (القياس ٢٠٢٦-١١-١٢: ٧٤٠ م.ث للواجهة مقابل ١٦ م.ث بعد حسابها مرة واحدة). الآن تُحسب مرة واحدة لكل استعلام (`me`)،
-- والأعمدة وترتيبها وأنواعها وقواعد الإخفاء كما هي تماماً. المالك والصلاحيات لا تتغيّر (CREATE OR REPLACE VIEW).
-- التراجع: supabase/rollback/20261112100000_members_masked_fast_rollback.sql

create or replace view public.members_masked as
with me as materialized (
  select auth.uid()                  as uid,
         public.current_profile_id() as pid,
         public.is_team(auth.uid())  as team,
         public.is_approved_member() as approved
)
select p.id,
       p.first_name,
       p.full_name,
       case when coalesce(p.is_phone_hidden, false) = false or p.id = me.uid or me.team
            then p.phone_number else null::text end as phone_number,
       case when coalesce(p.is_birth_date_hidden, false) = false or p.id = me.uid or p.id = me.pid or me.team
            then p.birth_date else null::date end as birth_date,
       p.death_date,
       p.is_deceased,
       p.role,
       p.father_id,
       case when coalesce(p.is_photo_hidden, false) = false or p.id = me.uid or p.id = me.pid or me.team
            then p.photo_url else null::text end as photo_url,
       p.is_phone_hidden,
       p.is_hidden_from_tree,
       p.sort_order,
       p.bio_json,
       p.sons_ids,
       p.status,
       p.created_at,
       p.is_married,
       case when coalesce(p.is_photo_hidden, false) = false or p.id = me.uid or p.id = me.pid or me.team
            then p.avatar_url else null::text end as avatar_url,
       p.bio,
       p.is_approved,
       p.is_admin,
       p.is_phone_verified,
       p.is_birth_date_hidden,
       p.cover_url,
       p.badge_enabled,
       p.gender,
       p.updated_by,
       p.updated_at,
       p.is_hr_member,
       p.hr_status,
       case when coalesce(p.activity_visible, true) or p.id = me.uid or p.id = me.pid or me.team
            then p.last_seen_at else null::timestamp with time zone end as last_seen_at,
       case when p.id = me.uid or p.id = me.pid or me.team
            then p.registration_platform else null::text end as registration_platform,
       p.username,
       case when coalesce(p.activity_visible, true) or p.id = me.uid or p.id = me.pid or me.team
            then p.last_active_at else null::timestamp with time zone end as last_active_at,
       case when p.id = me.uid or p.id = me.pid or me.team
            then p.current_screen else null::text end as current_screen,
       case when p.id = me.uid or p.id = me.pid or me.team
            then p.current_screen_source else null::text end as current_screen_source,
       case when p.id = me.uid or me.team
            then p.email else null::text end as email,
       p.mother_id,
       p.husband_id,
       p.terms_accepted_at,
       p.family_name,
       p.death_date_unknown,
       p.avatar_unavailable,
       p.is_photo_hidden,
       p.activity_visible
from public.profiles p
cross join me
where me.uid is not null and (p.id = me.uid or me.approved);
