-- Backup server-side notification when a child profile is created.
-- This makes admin notification reliable even if admin_requests insert fails.

create or replace function public.notify_admins_on_child_profile_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  admin_profile_id uuid;
  title_text text;
  body_text text;
begin
  -- Notify only when profile has a father (child linked in tree).
  if new.father_id is null then
    return new;
  end if;

  title_text := 'إضافة ابن جديد';
  body_text := format('تمت إضافة ابن جديد في الشجرة: %s', coalesce(new.full_name, new.first_name, 'عضو جديد'));

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
      'child_add',
      new.father_id
    );
  end loop;

  return new;
end;
$$;

drop trigger if exists profiles_notify_admins_child_add on public.profiles;

create trigger profiles_notify_admins_child_add
after insert on public.profiles
for each row
execute function public.notify_admins_on_child_profile_insert();
