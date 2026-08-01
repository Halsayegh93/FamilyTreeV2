-- تحسين: استخدام auth.sessions.updated_at لتعريف "نشط" أدق
-- last_sign_in_at يُحدّث فقط عند login جديد، بينما sessions.updated_at يُحدّث عند كل refresh

-- لازم نحذف الدالة القديمة لأن الـ return type تغيّر
drop function if exists public.get_members_activity(uuid[]);

create or replace function public.get_members_activity(member_ids uuid[])
returns table (
  member_id uuid,
  last_sign_in_at timestamptz,
  last_session_at timestamptz,
  last_device_active timestamptz,
  is_active boolean,
  days_since_active int
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  threshold timestamptz := now() - interval '30 days';
begin
  if not (public.current_user_role() in ('owner', 'admin', 'monitor', 'supervisor')) then
    raise exception 'Permission denied: only moderators can query activity';
  end if;

  return query
  select
    p.id,
    au.last_sign_in_at,
    (select max(s.updated_at) from auth.sessions s where s.user_id = p.id) as last_session,
    (select max(dt.updated_at) from public.device_tokens dt where dt.member_id = p.id),
    case
      -- ١) آخر تسجيل دخول قريب
      when au.last_sign_in_at is not null and au.last_sign_in_at > threshold then true
      -- ٢) جلسة محدّثة قريباً (refresh token)
      when exists (
        select 1 from auth.sessions s
        where s.user_id = p.id and s.updated_at > threshold
      ) then true
      -- ٣) جهاز iOS مسجّل قريباً
      when exists (
        select 1 from public.device_tokens dt
        where dt.member_id = p.id and dt.updated_at > threshold
      ) then true
      else false
    end,
    case
      -- نحسب الأيام من أحدث نشاط متاح
      when au.last_sign_in_at is null
        and not exists (select 1 from auth.sessions s where s.user_id = p.id)
      then null
      else extract(day from (now() - greatest(
        coalesce(au.last_sign_in_at, '1970-01-01'::timestamptz),
        coalesce((select max(s.updated_at) from auth.sessions s where s.user_id = p.id), '1970-01-01'::timestamptz)
      )))::int
    end
  from public.profiles p
  left join auth.users au on au.id = p.id
  where p.id = any(member_ids);
end;
$$;

grant execute on function public.get_members_activity(uuid[]) to authenticated;
