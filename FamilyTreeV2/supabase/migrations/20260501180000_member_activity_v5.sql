-- v5: إصلاح فحص الصلاحية — استعلام role مباشرة بدلاً من current_user_role()
-- المشكلة كانت: current_user_role() داخل SECURITY DEFINER لا تُرجع القيمة الصحيحة دائماً

drop function if exists public.get_members_activity(uuid[]);

create or replace function public.get_members_activity(member_ids uuid[])
returns table (
  member_id uuid,
  last_active_at timestamptz,
  last_device_active timestamptz,
  is_active boolean,
  days_since_active int
)
language plpgsql
security definer
set search_path = public
as $$
declare
  threshold timestamptz := now() - interval '14 days';
  caller_role text;
  caller_uid uuid := auth.uid();
begin
  if caller_uid is null then
    raise exception 'Not authenticated';
  end if;

  -- جلب الدور مباشرة بدل current_user_role() لتجنب مشاكل context
  select role into caller_role
  from public.profiles
  where id = caller_uid;

  if caller_role is null then
    raise exception 'Caller profile not found (uid=%)', caller_uid;
  end if;

  if caller_role not in ('owner', 'admin', 'monitor', 'supervisor') then
    raise exception 'Permission denied (your role is %)', caller_role;
  end if;

  return query
  select
    p.id,
    p.last_active_at,
    (select max(dt.updated_at) from public.device_tokens dt where dt.member_id = p.id) as last_device,
    case
      when p.last_active_at > threshold then true
      when exists (
        select 1 from public.device_tokens dt
        where dt.member_id = p.id and dt.updated_at > threshold
      ) then true
      else false
    end as is_active,
    case
      when p.last_active_at is null then null
      else extract(day from (now() - p.last_active_at))::int
    end as days_since_active
  from public.profiles p
  where p.id = any(member_ids);
end;
$$;

grant execute on function public.get_members_activity(uuid[]) to authenticated;
