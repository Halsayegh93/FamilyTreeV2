-- Auto-mirror any male son added to the classic tree (profiles)
-- into the women/drill-down tree (women_members), keeping the SAME id
-- so photos stay live-linked by id. Wives/mothers/daughters that live
-- only in women_members are never touched.

create or replace function public.mirror_profile_to_women()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Only mirror people that belong on the tree: a son linked to a father,
  -- and only males (gender male, or unset which defaults to male).
  if new.father_id is null then
    return new;
  end if;
  if new.gender is not null and lower(new.gender) <> 'male' then
    return new;
  end if;

  insert into public.women_members (
    id, first_name, full_name, parent_id, gender,
    is_deceased, birth_date, death_date, is_hidden_from_tree,
    sort_order, photo_url, avatar_url
  ) values (
    new.id,
    coalesce(new.first_name, ''),
    coalesce(nullif(new.full_name, ''), new.first_name, ''),
    new.father_id,
    'male',
    coalesce(new.is_deceased, false),
    new.birth_date,
    new.death_date,
    coalesce(new.is_hidden_from_tree, false),
    coalesce(new.sort_order, 0),
    new.photo_url,
    new.avatar_url
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists trg_mirror_profile_to_women on public.profiles;
create trigger trg_mirror_profile_to_women
after insert on public.profiles
for each row
execute function public.mirror_profile_to_women();;
