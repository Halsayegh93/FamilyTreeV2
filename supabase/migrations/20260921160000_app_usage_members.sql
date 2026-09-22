-- قائمة الأعضاء في كل فئة من فئات «استخدام التطبيق» (طلب المالك)
--
-- نفس تصنيف app_usage_stats() — تُفتح من بطاقة «استخدام التطبيق» في لوحة الإدارة
-- لمعرفة «من هم» ولماذا (آخر دخول، هل له حساب). لفريق الإدارة فقط.
-- p_category: active | idle_3_6 | idle_6_plus | login_no_device | never_logged | no_phone

create or replace function public.app_usage_members(p_category text)
returns table (
  member_id uuid, full_name text, phone text,
  last_seen timestamptz, account_created timestamptz, has_login boolean
)
language sql
stable
security definer
set search_path = public
as $$
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
        when has_device and last_seen >= now() - interval '3 months' then 'active'
        when has_device and last_seen >= now() - interval '6 months' then 'idle_3_6'
        when has_device then 'idle_6_plus'
        when has_login then 'login_no_device'
        else 'never_logged'
      end as category
    from act
  )
  select id, full_name, phone_number, last_seen, account_created, has_login
  from cat
  where category = p_category and public.is_moderator()
  order by last_seen desc nulls last, full_name;
$$;

revoke all on function public.app_usage_members(text) from public, anon;
grant execute on function public.app_usage_members(text) to authenticated;
