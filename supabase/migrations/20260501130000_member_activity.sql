-- ╔════════════════════════════════════════════════════════════════════════╗
-- ║ تتبع نشاط الأعضاء — اكتشاف غير النشطين                              ║
-- ║ يستخدم auth.users.last_sign_in_at + device_tokens                     ║
-- ╚════════════════════════════════════════════════════════════════════════╝

-- RPC function: آخر نشاط لمجموعة أعضاء (للمدراء فقط)
create or replace function public.get_members_activity(member_ids uuid[])
returns table (
  member_id uuid,
  last_sign_in_at timestamptz,
  last_device_active timestamptz,
  is_active boolean,
  days_since_active int
)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  -- التحقق من الصلاحيات
  if not (public.current_user_role() in ('owner', 'admin', 'monitor', 'supervisor')) then
    raise exception 'Permission denied: only moderators can query activity';
  end if;

  return query
  select
    p.id,
    au.last_sign_in_at,
    (select max(dt.updated_at) from public.device_tokens dt where dt.member_id = p.id),
    case
      when au.last_sign_in_at is not null and au.last_sign_in_at > now() - interval '30 days' then true
      when exists (
        select 1 from public.device_tokens dt
        where dt.member_id = p.id and dt.updated_at > now() - interval '30 days'
      ) then true
      else false
    end,
    case
      when au.last_sign_in_at is null then null
      else extract(day from (now() - au.last_sign_in_at))::int
    end
  from public.profiles p
  left join auth.users au on au.id = p.id
  where p.id = any(member_ids);
end;
$$;

grant execute on function public.get_members_activity(uuid[]) to authenticated;
