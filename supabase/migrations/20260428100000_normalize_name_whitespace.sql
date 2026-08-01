-- Normalize whitespace in member names:
-- collapse multiple consecutive spaces into one, and trim leading/trailing spaces.
-- Uses regexp_replace with 'g' flag: '\s+' → ' '

-- One-time cleanup of existing data
UPDATE public.profiles
SET
  full_name  = trim(regexp_replace(full_name,  '\s+', ' ', 'g')),
  first_name = trim(regexp_replace(first_name, '\s+', ' ', 'g'))
WHERE
  full_name  ~ '\s{2,}' OR full_name  <> trim(full_name)
  OR first_name ~ '\s{2,}' OR first_name <> trim(first_name);

-- Trigger function: auto-normalise on every INSERT or UPDATE
create or replace function public.normalize_profile_names()
returns trigger language plpgsql as $$
begin
  new.full_name  := trim(regexp_replace(new.full_name,  '\s+', ' ', 'g'));
  new.first_name := trim(regexp_replace(new.first_name, '\s+', ' ', 'g'));
  return new;
end;
$$;

-- Attach trigger to profiles table (fires before insert or update on name columns)
drop trigger if exists trg_normalize_profile_names on public.profiles;
create trigger trg_normalize_profile_names
  before insert or update of full_name, first_name
  on public.profiles
  for each row execute function public.normalize_profile_names();
