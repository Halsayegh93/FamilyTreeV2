-- التراجع عن 20261112100000_members_masked_fast — يرجع تعريف `members_masked` كما كان حرفياً (٢٠٢٦-١١-١٢)
create or replace view public.members_masked as
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
        CASE
            WHEN COALESCE(activity_visible, true) OR id = auth.uid() OR id = current_profile_id() OR is_team(auth.uid()) THEN last_seen_at
            ELSE NULL::timestamp with time zone
        END AS last_seen_at,
        CASE
            WHEN id = auth.uid() OR id = current_profile_id() OR is_team(auth.uid()) THEN registration_platform
            ELSE NULL::text
        END AS registration_platform,
    username,
        CASE
            WHEN COALESCE(activity_visible, true) OR id = auth.uid() OR id = current_profile_id() OR is_team(auth.uid()) THEN last_active_at
            ELSE NULL::timestamp with time zone
        END AS last_active_at,
        CASE
            WHEN id = auth.uid() OR id = current_profile_id() OR is_team(auth.uid()) THEN current_screen
            ELSE NULL::text
        END AS current_screen,
        CASE
            WHEN id = auth.uid() OR id = current_profile_id() OR is_team(auth.uid()) THEN current_screen_source
            ELSE NULL::text
        END AS current_screen_source,
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
    is_photo_hidden,
    activity_visible
   FROM profiles p
  WHERE auth.uid() IS NOT NULL AND (id = auth.uid() OR is_approved_member());
