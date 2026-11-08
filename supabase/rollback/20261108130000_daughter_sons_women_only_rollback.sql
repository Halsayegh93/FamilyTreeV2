-- تراجع 20261108130000_daughter_sons_women_only
drop trigger if exists trg_daughter_son_women_only on public.profiles;
drop function if exists private.daughter_son_women_only();

-- الدالتان كما كانتا حرفياً قبل الترحيل
create or replace function public.app_usage_stats()
 returns table(active integer, idle integer, login_no_device integer, never_logged integer, no_phone integer)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  with alive as (
    select p.id, nullif(trim(p.phone_number), '') is not null as has_phone
    from public.profiles p
    where coalesce(p.is_deceased, false) = false and p.role <> 'pending'
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

create or replace function public.app_usage_members(p_category text)
 returns table(member_id uuid, full_name text, phone text, last_seen timestamp with time zone, account_created timestamp with time zone, has_login boolean)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  with alive as (
    select p.id, p.full_name, p.phone_number,
           nullif(trim(p.phone_number), '') is not null as has_phone
    from public.profiles p
    where coalesce(p.is_deceased, false) = false and p.role <> 'pending'
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
