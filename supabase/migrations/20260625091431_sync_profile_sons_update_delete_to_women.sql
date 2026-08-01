-- Keep women_members mirror in sync on UPDATE and DELETE of profiles.
-- Only affects the mirrored row (matched by SAME id). Wives/mothers/daughters
-- that exist only in women_members are never touched (their ids are not in profiles).

-- UPDATE: re-sync the mirrored son (name, father link, deceased, dates).
create or replace function public.sync_profile_update_to_women()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- If it now qualifies as a male son, ensure a mirror exists / is updated.
  if new.father_id is not null
     and (new.gender is null or lower(new.gender) = 'male') then
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
      new.birth_date, new.death_date,
      coalesce(new.is_hidden_from_tree, false),
      coalesce(new.sort_order, 0),
      new.photo_url, new.avatar_url
    )
    on conflict (id) do update set
      first_name        = excluded.first_name,
      full_name         = excluded.full_name,
      parent_id         = excluded.parent_id,
      is_deceased       = excluded.is_deceased,
      birth_date        = excluded.birth_date,
      death_date        = excluded.death_date,
      is_hidden_from_tree = excluded.is_hidden_from_tree;
  else
    -- No longer a male son (e.g. father removed) -> drop the mirrored row.
    delete from public.women_members where id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sync_profile_update_to_women on public.profiles;
create trigger trg_sync_profile_update_to_women
after update on public.profiles
for each row
when (
  old.father_id is distinct from new.father_id
  or old.first_name is distinct from new.first_name
  or old.full_name is distinct from new.full_name
  or old.gender is distinct from new.gender
  or old.is_deceased is distinct from new.is_deceased
  or old.birth_date is distinct from new.birth_date
  or old.death_date is distinct from new.death_date
  or old.is_hidden_from_tree is distinct from new.is_hidden_from_tree
)
execute function public.sync_profile_update_to_women();

-- DELETE: remove the mirrored son from the women tree.
create or replace function public.sync_profile_delete_to_women()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.women_members where id = old.id;
  return old;
end;
$$;

drop trigger if exists trg_sync_profile_delete_to_women on public.profiles;
create trigger trg_sync_profile_delete_to_women
after delete on public.profiles
for each row
execute function public.sync_profile_delete_to_women();;
