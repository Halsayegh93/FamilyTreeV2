-- خصوصية الحضور (طلب المالك ٢٠٢٦-١٠-٢٩ «نعم اصلح»):
-- • profiles.activity_visible — العضو يخفي «آخر ظهور/آخر نشاط» عن باقي الأعضاء (الإدارة تبقى تراه).
-- • members_masked: الشاشة الحالية ومنصة التسجيل لا تظهر إلا لصاحبها والإدارة؛ آخر ظهور/نشاط يُخفى إذا activity_visible=false.
-- • أي كتابة لـ current_screen لعضو أخفى نشاطه تُحفظ NULL (update_my_current_screen أصلاً لا يحفظ الشاشة منذ 20261027150000).

alter table public.profiles add column if not exists activity_visible boolean not null default true;

create or replace function public.trg_profiles_activity_privacy()
returns trigger language plpgsql set search_path to 'public' as $$
begin
  if new.activity_visible is false then
    new.current_screen := null;
    new.current_screen_source := null;
  end if;
  return new;
end $$;

drop trigger if exists trg_profiles_activity_privacy on public.profiles;
create trigger trg_profiles_activity_privacy
  before insert or update of current_screen, current_screen_source, activity_visible on public.profiles
  for each row execute function public.trg_profiles_activity_privacy();

create or replace function public.set_activity_visibility(p_visible boolean)
returns boolean language plpgsql security definer set search_path to 'public' as $$
declare me uuid := public.current_profile_id(); v boolean;
begin
  if auth.uid() is null or me is null then
    raise exception 'not_authenticated' using errcode = '42501', hint = 'not_authenticated';
  end if;
  if p_visible is null then
    raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload';
  end if;
  update public.profiles set activity_visible = p_visible where id = me returning activity_visible into v;
  if not found then
    raise exception 'no_profile' using errcode = 'P0002', hint = 'no_profile';
  end if;
  return v;
end $$;
revoke all on function public.set_activity_visibility(boolean) from public, anon;
grant execute on function public.set_activity_visibility(boolean) to authenticated;

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
