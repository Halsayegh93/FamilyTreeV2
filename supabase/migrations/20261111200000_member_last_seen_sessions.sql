-- «آخر دخول» يشمل تجديد الجلسة (طلب المالك ٢٠٢٦-١١-١١: «صلحه و صلح بقية الاعضاء وتاكد من تاريخ الدخول»)
--
-- المشكلة: «آخر دخول» كان = الأحدث من (آخر تسجيل برمز التحقق `auth.users.last_sign_in_at`، آخر تحديث لتسجيل الجهاز
-- `device_tokens.updated_at`). الجلسة تبقى مفتوحة شهوراً فلا يتغيّر الأول، والثاني لا يتغيّر ما دام رمز الإشعارات ثابتاً —
-- فعضو يفتح التطبيق يومياً ظهر في «لم يدخلوا التطبيق منذ 21 يوماً» (عبدالله سعود: فتحه اليوم، والحساب يقول 11 سبتمبر).
-- الحل: إشارة ثالثة — آخر تجديد للجلسة (`auth.sessions.updated_at`، يتحدّث كلما فتح التطبيق وجدّد رمزه).
-- وربط الحساب بالعضو كما في `current_profile_id()`: `app_metadata.profile_id` إن وُجد، وإلا معرّف الحساب نفسه
-- (حساب نُقل إلى ملف شجرة آخر كان يُحسب «لم يسجّل» لأن الربط كان بالمعرّف فقط).
--
-- مكان واحد: `private.member_activity()` — تقرؤه الدوال الأربع: app_usage_members · app_usage_stats ·
-- app_usage_count_since (العدّ اليومي) · get_members_last_signin. الفئات وقاعدة الـ21 يوماً والصلاحيات كما هي.
-- لا تغيير في الجداول ولا كتابة بيانات. التراجع: supabase/rollback/20261111200000_member_last_seen_sessions_rollback.sql

create schema if not exists private;

create or replace function private.member_activity()
returns table(member_id uuid, has_login boolean, account_created timestamptz, last_seen timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  with acct as (
    select case when u.raw_app_meta_data ->> 'profile_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                then (u.raw_app_meta_data ->> 'profile_id')::uuid
                else u.id end as member_id,
           u.id as user_id, u.created_at, u.last_sign_in_at
    from auth.users u
  ), sess as (
    select s.user_id, max(s.updated_at) as seen
    from auth.sessions s
    group by s.user_id
  ), per_member as (
    select a.member_id,
           min(a.created_at) as account_created,
           max(greatest(a.last_sign_in_at, s.seen)) as seen
    from acct a
    left join sess s on s.user_id = a.user_id
    group by a.member_id
  ), dev as (
    select d.member_id, max(d.updated_at) as seen
    from public.device_tokens d
    group by d.member_id
  )
  select coalesce(p.member_id, d.member_id),
         p.member_id is not null,
         p.account_created,
         greatest(p.seen, d.seen)
  from per_member p
  full join dev d on d.member_id = p.member_id;
$$;

revoke all on function private.member_activity() from public, anon, authenticated;

-- ١) قائمة الأعضاء حسب الفئة
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
      coalesce(m.has_login, false) as has_login,
      m.account_created,
      m.last_seen
    from alive a
    left join private.member_activity() m on m.member_id = a.id
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

-- ٢) أعداد الفئات
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
      coalesce(m.has_login, false) as has_login,
      m.last_seen
    from alive a
    left join private.member_activity() m on m.member_id = a.id
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

-- ٣) العدّ اليومي (record_app_usage_day و app_usage_trend)
create or replace function public.app_usage_count_since(p_since timestamptz)
returns integer
language sql
stable
set search_path to ''
as $function$
  select count(*)::int
    from public.profiles p
    join private.member_activity() m on m.member_id = p.id
   where coalesce(p.is_deceased, false) = false
     and p.role <> 'pending'
     and nullif(trim(p.phone_number), '') is not null
     and exists (select 1 from public.device_tokens d where d.member_id = p.id)
     and m.last_seen >= p_since;
$function$;

-- ٤) آخر دخول لكل عضو (ورقة العضو وقوائم الإدارة)
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
  select m.member_id, m.last_seen
  from private.member_activity() m
  where m.member_id is not null and m.last_seen is not null;
end;
$function$;
