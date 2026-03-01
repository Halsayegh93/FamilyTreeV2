-- Server-side fix for phone-based identity matching:
-- 1) Normalize all profile phone numbers to Kuwaiti local 8 digits.
-- 2) Merge duplicate profiles that share the same normalized phone.
-- 3) Enforce uniqueness for non-empty phone_number.
-- 4) Normalize incoming phone numbers automatically via trigger.

create or replace function public.normalize_kuwait_phone(raw text)
returns text
language plpgsql
immutable
as $$
declare
  digits text;
begin
  if raw is null then
    return null;
  end if;

  digits := regexp_replace(raw, '\\D', '', 'g');

  if digits like '00965%' and length(digits) > 8 then
    digits := substr(digits, 6);
  elsif digits like '965%' and length(digits) > 8 then
    digits := substr(digits, 4);
  end if;

  if length(digits) > 8 then
    digits := substr(digits, 1, 8);
  end if;

  if length(digits) = 8 then
    return digits;
  end if;

  return null;
end;
$$;

-- Normalize existing data first.
update public.profiles
set phone_number = public.normalize_kuwait_phone(phone_number)
where phone_number is not null;

-- Merge duplicate profiles by normalized phone number.
do $$
declare
  r record;
  keep_id uuid;
  dup_id uuid;
begin
  for r in
    select phone_number
    from public.profiles
    where phone_number is not null and phone_number <> ''
    group by phone_number
    having count(*) > 1
  loop
    select p.id
    into keep_id
    from public.profiles p
    where p.phone_number = r.phone_number
    order by
      (p.status = 'active') desc,
      (p.role <> 'pending') desc,
      p.created_at asc,
      p.id asc
    limit 1;

    for dup_id in
      select p.id
      from public.profiles p
      where p.phone_number = r.phone_number
        and p.id <> keep_id
    loop
      -- Rewire self-reference first.
      update public.profiles set father_id = keep_id where father_id = dup_id;

      -- Rewire foreign keys in related tables.
      update public.admin_requests set member_id = keep_id where member_id = dup_id;
      update public.admin_requests set requester_id = keep_id where requester_id = dup_id;

      update public.news set author_id = keep_id where author_id = dup_id;
      update public.news set approved_by = keep_id where approved_by = dup_id;

      update public.diwaniyas set owner_id = keep_id where owner_id = dup_id;
      update public.diwaniyas set approved_by = keep_id where approved_by = dup_id;

      update public.notifications set target_member_id = keep_id where target_member_id = dup_id;
      update public.notifications set created_by = keep_id where created_by = dup_id;

      -- Remove duplicate profile row.
      delete from public.profiles where id = dup_id;
    end loop;
  end loop;
end;
$$;

-- Enforce valid format for stored phones.
alter table public.profiles
  drop constraint if exists profiles_phone_number_kuwait_ck;

alter table public.profiles
  add constraint profiles_phone_number_kuwait_ck
  check (phone_number is null or phone_number ~ '^[0-9]{8}$');

-- Enforce uniqueness for non-empty phones.
create unique index if not exists idx_profiles_phone_number_unique
  on public.profiles (phone_number)
  where phone_number is not null and phone_number <> '';

-- Auto-normalize on future inserts/updates.
create or replace function public.trg_profiles_normalize_phone()
returns trigger
language plpgsql
as $$
begin
  new.phone_number := public.normalize_kuwait_phone(new.phone_number);
  return new;
end;
$$;

drop trigger if exists profiles_normalize_phone on public.profiles;

create trigger profiles_normalize_phone
before insert or update of phone_number on public.profiles
for each row
execute function public.trg_profiles_normalize_phone();
