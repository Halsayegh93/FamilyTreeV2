-- Security fix: prevent users from self-promoting their role or status.
-- Only admins/supervisors can change role and status fields.
-- Regular members can update their own profile but NOT role/status.

-- Drop the old permissive policy
drop policy if exists "profiles_update_self_or_moderator" on public.profiles;

-- Create a trigger function to prevent role/status self-promotion
create or replace function public.prevent_role_self_promotion()
returns trigger as $$
begin
  -- If the user is NOT a moderator (admin/supervisor), block role/status changes
  if public.current_user_role() not in ('admin', 'supervisor') then
    -- Force role and status to remain unchanged for non-moderators
    new.role := old.role;
    new.status := old.status;
  end if;
  return new;
end;
$$ language plpgsql security definer;

-- Create trigger on profiles table
drop trigger if exists trg_prevent_role_self_promotion on public.profiles;
create trigger trg_prevent_role_self_promotion
  before update on public.profiles
  for each row
  execute function public.prevent_role_self_promotion();

-- Recreate the update policy (same as before)
create policy "profiles_update_self_or_moderator" on public.profiles
for update
using (
  id = auth.uid()
  or public.current_user_role() in ('supervisor', 'admin')
)
with check (
  id = auth.uid()
  or public.current_user_role() in ('supervisor', 'admin')
);
