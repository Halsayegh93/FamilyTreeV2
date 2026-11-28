-- تراجع 20261111200000_member_last_seen_sessions: يعيد الدوال الأربع حرفياً كما كانت حيّة قبل ٢٠٢٦-١١-١١ ويحذف المساعد.

create or replace function public.app_usage_members(p_category text)
returns table(member_id uuid, full_name text, phone text, last_seen timestamptz, account_created timestamptz, has_login boolean)
language sql
stable
security definer
set search_path to 'public'
as $function$
  with alive as (
    select p.id, p.full_name, p.phone_number,
           nullif(trim(p.phone_number), '') is not null as has_phone
    from public.profiles p
    where coalesce(p.is_deceased, false) = false and p.role <> 'pending'
      -- «فرع خارج العائلة» (أبناء البنات) لا يُعدّون في أرقام العائلة
      and not exists (select 1 from public.daughter_son_lineage d where d.profile_id = p.id)
  ), act as (
    select a.*,
      exists (select 1 from public.device_tokens d where d.member_id = a.id) as has_device,
      u.id is not null as has_login,
      u.created_at as account_created,
      greatest(u.last_sign_in_at,
               (select max(d.updated_at) from public.device_tokens d where d.member_id = a.id)) as last_seen
    from alive a
    left join auth.users u on u.id = a.id
  ), cat as (
    select act.*,
      case
        when not has_phone then 'no_phone'
        when has_device and last_seen >= now() - interval '21 days' then 'active'
        when has_device then 'idle'
        when has_login then 'login_no_device'
        else 'never_logged'
      end as category
    from act
  )
  select id, full_name, phone_number, last_seen, account_created, has_login
  from cat
  where category = p_category and public.is_moderator()
  order by last_seen desc nulls last, full_name;
$function$;

create or replace function public.app_usage_stats()
returns table(active integer, idle integer, login_no_device integer, never_logged integer, no_phone integer)
language sql
stable
security definer
set search_path to 'public'
as $function$
  with alive as (
    select p.id, nullif(trim(p.phone_number), '') is not null as has_phone
    from public.profiles p
    where coalesce(p.is_deceased, false) = false and p.role <> 'pending'
      -- «فرع خارج العائلة» (أبناء البنات) لا يُعدّون في أرقام العائلة
      and not exists (select 1 from public.daughter_son_lineage d where d.profile_id = p.id)
  ), act as (
    select a.id, a.has_phone,
      exists (select 1 from public.device_tokens d where d.member_id = a.id) as has_device,
      u.id is not null as has_login,
      greatest(u.last_sign_in_at,
               (select max(d.updated_at) from public.device_tokens d where d.member_id = a.id)) as last_seen
    from alive a
    left join auth.users u on u.id = a.id
  )
  select
    (count(*) filter (where has_phone and has_device and last_seen >= now() - interval '21 days'))::int,
    (count(*) filter (where has_phone and has_device and (last_seen < now() - interval '21 days' or last_seen is null)))::int,
    (count(*) filter (where has_phone and has_login and not has_device))::int,
    (count(*) filter (where has_phone and not has_login and not has_device))::int,
    (count(*) filter (where not has_phone))::int
  from act
  where public.is_moderator();
$function$;

create or replace function public.app_usage_count_since(p_since timestamptz)
returns integer
language sql
stable
set search_path to ''
as $function$
  select count(*)::int
    from public.profiles p
    left join auth.users u on u.id = p.id
   where coalesce(p.is_deceased, false) = false
     and p.role <> 'pending'
     and nullif(trim(p.phone_number), '') is not null
     and exists (select 1 from public.device_tokens d where d.member_id = p.id)
     and greatest(u.last_sign_in_at,
                  (select max(d.updated_at) from public.device_tokens d where d.member_id = p.id)) >= p_since;
$function$;

create or replace function public.get_members_last_signin()
returns table(member_id uuid, last_sign_in_at timestamptz)
language plpgsql
security definer
set search_path to 'public', 'auth'
as $function$
declare
  caller_role text;
begin
  caller_role := public.current_user_role();
  if caller_role is null or caller_role not in ('owner', 'admin', 'monitor') then
    return;
  end if;

  return query
  with all_activity as (
    select u.id as mid, u.last_sign_in_at as ts
    from auth.users u
    where u.last_sign_in_at is not null
    union all
    -- دخول username: الربط من app_metadata (لا يعدّله المستخدم)
    select (u.raw_app_meta_data ->> 'profile_id')::uuid as mid, u.last_sign_in_at as ts
    from auth.users u
    where u.raw_app_meta_data ->> 'profile_id' is not null
      and u.last_sign_in_at is not null
    union all
    select dt.member_id as mid, dt.updated_at as ts
    from public.device_tokens dt
    where dt.updated_at is not null
  )
  select a.mid, max(a.ts)
  from all_activity a
  where a.mid is not null
  group by a.mid;
end;
$function$;

drop function if exists private.member_activity();
