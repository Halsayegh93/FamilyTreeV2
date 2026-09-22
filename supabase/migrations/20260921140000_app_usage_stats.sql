-- «يستخدمون التطبيق» — عدد من لهم حساب دخول فعلي (طلب المالك)
--
-- حالة «مفعّل» في profiles لا تعني أن العضو يستخدم التطبيق: أغلب الأحياء أسماء
-- في الشجرة بلا رقم ولا حساب. هذه الدالة تُرجع الأرقام الحقيقية لفريق الإدارة:
--   app_users   — أحياء لهم حساب دخول (auth.users)
--   with_device — أحياء لهم جهاز مسجّل يستقبل الإشعارات
--   with_phone  — أحياء لهم رقم جوال في الشجرة
-- security definer لأن auth.users غير مقروء للعميل؛ ولا تُرجع شيئاً لغير فريق الإدارة.

create or replace function public.app_usage_stats()
returns table (app_users int, with_device int, with_phone int)
language sql
stable
security definer
set search_path = public
as $$
  select
    (select count(*) from public.profiles p
       where coalesce(p.is_deceased, false) = false and p.role <> 'pending'
         and exists (select 1 from auth.users u where u.id = p.id))::int,
    (select count(distinct d.member_id) from public.device_tokens d
       join public.profiles p on p.id = d.member_id
       where coalesce(p.is_deceased, false) = false and p.role <> 'pending')::int,
    (select count(*) from public.profiles p
       where coalesce(p.is_deceased, false) = false and p.role <> 'pending'
         and nullif(trim(p.phone_number), '') is not null)::int
  where public.is_moderator();
$$;

revoke all on function public.app_usage_stats() from public, anon;
grant execute on function public.app_usage_stats() to authenticated;
