-- Fix: current_user_role() must work for web users who login via email/password
-- where auth.uid() differs from profiles.id (which is stored in user_metadata.profile_id)

create or replace function public.current_user_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select p.role
  from public.profiles p
  where p.id = coalesce(
    nullif(auth.jwt() -> 'user_metadata' ->> 'profile_id', '')::uuid,
    auth.uid()
  )
$$;
