-- «العضو الفعّال» = رقم جوال + جهاز دخل التطبيق (تعريف المالك) + تقسيم حسب آخر دخول
--
-- آخر ظهور = الأحدث بين آخر تسجيل دخول (auth.users.last_sign_in_at) وآخر تحديث
-- لجهاز العضو (device_tokens.updated_at يتجدد عند فتح التطبيق).
-- الفئات متنافية ومجموعها = الأحياء (عدا المعلّقين):
--   active          — رقم + جهاز + ظهر خلال ٣ أشهر
--   idle_3_6        — رقم + جهاز + آخر ظهور بين ٣ و٦ أشهر
--   idle_6_plus     — رقم + جهاز + آخر ظهور قبل أكثر من ٦ أشهر
--   login_no_device — رقم + حساب دخول بلا جهاز مسجّل
--   never_logged    — رقم بلا أي دخول
--   no_phone        — بلا رقم (أسماء في الشجرة فقط)

drop function if exists public.app_usage_stats();

create function public.app_usage_stats()
returns table (
  active int, idle_3_6 int, idle_6_plus int,
  login_no_device int, never_logged int, no_phone int
)
language sql
stable
security definer
set search_path = public
as $$
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
    (count(*) filter (where has_phone and has_device and last_seen >= now() - interval '3 months'))::int,
    (count(*) filter (where has_phone and has_device and last_seen <  now() - interval '3 months'
                                                   and last_seen >= now() - interval '6 months'))::int,
    (count(*) filter (where has_phone and has_device and (last_seen < now() - interval '6 months' or last_seen is null)))::int,
    (count(*) filter (where has_phone and has_login and not has_device))::int,
    (count(*) filter (where has_phone and not has_login and not has_device))::int,
    (count(*) filter (where not has_phone))::int
  from act
  where public.is_moderator();
$$;

revoke all on function public.app_usage_stats() from public, anon;
grant execute on function public.app_usage_stats() to authenticated;
