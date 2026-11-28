-- التراجع عن 20261127190000_member_category_access: السياسات الجديدة، ثم members_masked وlineage_locked كما كانا حرفياً
-- (20261112100000 و20261127160000)، ثم الدوال والفحص والمفتاح. outside_member_locked_sections لم يُمسّ فيبقى كما هو.
drop policy if exists news_member_access_insert on public.news;
drop policy if exists news_comments_member_access_insert on public.news_comments;
drop policy if exists news_likes_member_access_insert on public.news_likes;
drop policy if exists news_poll_votes_member_access_insert on public.news_poll_votes;
drop policy if exists diwaniyas_member_access_insert on public.diwaniyas;
drop policy if exists projects_member_access_insert on public.projects;
drop policy if exists family_archive_member_access_insert on public.family_archive;

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

create or replace function public.lineage_locked(p_section text)
 returns boolean
 language sql
 stable
 security definer
 set search_path to ''
as $function$
  select case
    when coalesce(public.current_user_role(), '') in ('owner', 'admin', 'monitor', 'supervisor') then false
    -- «صلاحيات محدودة» دائمة (الوالدة من خارج العائلة، 20261127160000): outside_member_locked_sections
    when exists (select 1 from public.daughter_son_lineage d
                  where d.profile_id = public.current_profile_id() and d.limited_at is not null)
      then coalesce((select case when jsonb_typeof(c.value) = 'array' then c.value ? p_section end
                       from public.app_config c where c.key = 'outside_member_locked_sections'),
                    p_section = any (array['diwaniyas', 'projects', 'library', 'women_tree', 'member_details']))
    -- «استكمال التسجيل» لم يُعتمد بعد: daughter_sons_locked_sections (كما كان)
    when exists (select 1 from public.daughter_son_lineage d
                  where d.profile_id = public.current_profile_id() and d.completed_at is null)
      then coalesce((select case when jsonb_typeof(c.value) = 'array' then c.value ? p_section end
                       from public.app_config c where c.key = 'daughter_sons_locked_sections'),
                    p_section = any (array['diwaniyas', 'projects', 'library', 'women_tree', 'member_details']))
    else false
  end;
$function$;
comment on function public.lineage_locked(text) is
  'Caller is a daughter''s son/daughter whose «استكمال التسجيل» is not approved yet (daughter_sons_locked_sections), or a limited member (outside_member_locked_sections). Used by RESTRICTIVE select policies.';
drop trigger if exists trg_app_config_member_access_guard on public.app_config;
delete from public.app_config where key = 'member_category_access';
drop function if exists public.member_access_allows(text);
drop function if exists public.my_member_category();
drop function if exists private.app_config_member_access_guard();
drop function if exists private.member_category_access_problem(jsonb);
drop function if exists private.member_access_protected(text);
drop function if exists private.member_access_categories();
drop function if exists private.member_access_keys();
