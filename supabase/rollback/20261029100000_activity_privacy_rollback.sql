-- تراجع 20261029100000_activity_privacy (الواجهة بنصّها السابق حرفياً)
begin;
drop trigger if exists trg_profiles_activity_privacy on public.profiles;
drop function if exists public.trg_profiles_activity_privacy();
drop function if exists public.set_activity_visibility(boolean);
drop view public.members_masked;
create view public.members_masked as
 SELECT id,
    first_name,
    full_name,
        CASE
            WHEN COALESCE(is_phone_hidden, false) = false OR id = auth.uid() OR is_team(auth.uid()) THEN phone_number
            ELSE NULL::text
        END AS phone_number,
        CASE
            WHEN COALESCE(is_birth_date_hidden, false) = false OR id = auth.uid() OR id = current_profile_id() OR is_team(auth.uid()) THEN birth_date
            ELSE NULL::date
        END AS birth_date,
    death_date,
    is_deceased,
    role,
    father_id,
        CASE
            WHEN COALESCE(is_photo_hidden, false) = false OR id = auth.uid() OR id = current_profile_id() OR is_team(auth.uid()) THEN photo_url
            ELSE NULL::text
        END AS photo_url,
    is_phone_hidden,
    is_hidden_from_tree,
    sort_order,
    bio_json,
    sons_ids,
    status,
    created_at,
    is_married,
        CASE
            WHEN COALESCE(is_photo_hidden, false) = false OR id = auth.uid() OR id = current_profile_id() OR is_team(auth.uid()) THEN avatar_url
            ELSE NULL::text
        END AS avatar_url,
    bio,
    is_approved,
    is_admin,
    is_phone_verified,
    is_birth_date_hidden,
    cover_url,
    badge_enabled,
    gender,
    updated_by,
    updated_at,
    is_hr_member,
    hr_status,
    last_seen_at,
    registration_platform,
    username,
    last_active_at,
    current_screen,
    current_screen_source,
        CASE
            WHEN id = auth.uid() OR is_team(auth.uid()) THEN email
            ELSE NULL::text
        END AS email,
    mother_id,
    husband_id,
    terms_accepted_at,
    family_name,
    death_date_unknown,
    avatar_unavailable,
    is_photo_hidden
   FROM profiles p
  WHERE auth.uid() IS NOT NULL AND (id = auth.uid() OR is_approved_member());
revoke all on public.members_masked from anon, authenticated;
grant select on public.members_masked to authenticated;
alter table public.profiles drop column if exists activity_visible;
commit;
