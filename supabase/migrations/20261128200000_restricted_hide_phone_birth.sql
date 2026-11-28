-- مطبَّق على الحي ٢٠٢٦-١١-٢٨ بعد تجربة begin…rollback: المقيّد (342cf2f6) ميلاد 458→1 (نفسه) وprofiles 2786→1؛ العضو والمالك بلا فرق.
-- قرار المالك «نعم اخفهم»: «لم يستكمل» و«مقيّد» لا يقرآن أرقام الأعضاء ولا تواريخ ميلادهم من السيرفر،
-- ولا جدول profiles إلا صفّهما (الأسماء والصور تبقى عبر members_masked للأخبار).

create or replace view public.members_masked as
 WITH me AS MATERIALIZED (
         SELECT auth.uid() AS uid,
            current_profile_id() AS pid,
            is_team(auth.uid()) AS team,
            is_approved_member() AS approved,
            member_access_allows('member_details.contact'::text) AS contact_ok,
            coalesce(my_member_category(), '') in ('incomplete', 'limited') AS restricted
        )
 SELECT p.id,
    p.first_name,
    p.full_name,
        CASE
            WHEN (((COALESCE(p.is_phone_hidden, false) = false) AND me.contact_ok AND NOT me.restricted) OR (p.id = me.uid) OR (p.id = me.pid) OR me.team) THEN p.phone_number
            ELSE NULL::text
        END AS phone_number,
        CASE
            WHEN (((COALESCE(p.is_birth_date_hidden, false) = false) AND NOT me.restricted) OR (p.id = me.uid) OR (p.id = me.pid) OR me.team) THEN p.birth_date
            ELSE NULL::date
        END AS birth_date,
    p.death_date,
    p.is_deceased,
    p.role,
    p.father_id,
        CASE
            WHEN ((COALESCE(p.is_photo_hidden, false) = false) OR (p.id = me.uid) OR (p.id = me.pid) OR me.team) THEN p.photo_url
            ELSE NULL::text
        END AS photo_url,
    p.is_phone_hidden,
    p.is_hidden_from_tree,
    p.sort_order,
    p.bio_json,
    p.sons_ids,
    p.status,
    p.created_at,
    p.is_married,
        CASE
            WHEN ((COALESCE(p.is_photo_hidden, false) = false) OR (p.id = me.uid) OR (p.id = me.pid) OR me.team) THEN p.avatar_url
            ELSE NULL::text
        END AS avatar_url,
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
        CASE
            WHEN (COALESCE(p.activity_visible, true) OR (p.id = me.uid) OR (p.id = me.pid) OR me.team) THEN p.last_seen_at
            ELSE NULL::timestamp with time zone
        END AS last_seen_at,
        CASE
            WHEN ((p.id = me.uid) OR (p.id = me.pid) OR me.team) THEN p.registration_platform
            ELSE NULL::text
        END AS registration_platform,
    p.username,
        CASE
            WHEN (COALESCE(p.activity_visible, true) OR (p.id = me.uid) OR (p.id = me.pid) OR me.team) THEN p.last_active_at
            ELSE NULL::timestamp with time zone
        END AS last_active_at,
        CASE
            WHEN ((p.id = me.uid) OR (p.id = me.pid) OR me.team) THEN p.current_screen
            ELSE NULL::text
        END AS current_screen,
        CASE
            WHEN ((p.id = me.uid) OR (p.id = me.pid) OR me.team) THEN p.current_screen_source
            ELSE NULL::text
        END AS current_screen_source,
        CASE
            WHEN ((p.id = me.uid) OR me.team) THEN p.email
            ELSE NULL::text
        END AS email,
    p.mother_id,
    p.husband_id,
    p.terms_accepted_at,
    p.family_name,
    p.death_date_unknown,
    p.avatar_unavailable,
    p.is_photo_hidden,
    p.activity_visible
   FROM (profiles p
     CROSS JOIN me)
  WHERE ((me.uid IS NOT NULL) AND ((p.id = me.uid) OR me.approved));

drop policy if exists profiles_restricted_own_row on public.profiles;
create policy profiles_restricted_own_row on public.profiles as restrictive for select to authenticated
  using (
    not coalesce((select public.my_member_category()) in ('incomplete', 'limited'), false)
    or id = (select auth.uid()) or id = (select public.current_profile_id())
  );
