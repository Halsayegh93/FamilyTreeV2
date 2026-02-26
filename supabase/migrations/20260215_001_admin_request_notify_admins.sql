-- Notify admins when any new admin request/report is created.
-- This ensures managers see alerts in Notifications screen automatically.

create or replace function public.notify_admins_on_admin_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  admin_profile_id uuid;
  requester_name text;
  title_text text;
  body_text text;
begin
  -- Only notify on newly created pending requests.
  if coalesce(new.status, '') <> 'pending' then
    return new;
  end if;

  select p.full_name
  into requester_name
  from public.profiles p
  where p.id = new.member_id;

  requester_name := coalesce(nullif(trim(requester_name), ''), 'عضو');

  title_text := 'طلب إداري جديد';
  body_text := format('%s أرسل طلباً جديداً (%s) ويحتاج مراجعة الإدارة.', requester_name, new.request_type);

  for admin_profile_id in
    select p.id
    from public.profiles p
    where p.role = 'admin'
  loop
    insert into public.notifications (
      target_member_id,
      title,
      body,
      kind,
      created_by
    ) values (
      admin_profile_id,
      title_text,
      body_text,
      'admin_request',
      new.requester_id
    );
  end loop;

  return new;
end;
$$;

drop trigger if exists admin_requests_notify_admins on public.admin_requests;

create trigger admin_requests_notify_admins
after insert on public.admin_requests
for each row
execute function public.notify_admins_on_admin_request();
