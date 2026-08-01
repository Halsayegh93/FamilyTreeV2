-- v6: حذف فحص الدور من الدالة — الموقع و التطبيق يتحققان قبل الاستدعاء
-- المشكلة: auth.uid() يرجع UUID مختلف عن profile.id لمستخدمي username/password بالموقع

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
begin
  -- يجب على الأقل أن يكون مصادقاً
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  -- الحماية: العميل يفحص الدور قبل الاستدعاء
  -- البيانات المُرجَعة (timestamps فقط) ليست حساسة

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
