-- Fix: include all moderator roles (owner, admin, monitor, supervisor)
-- in device_tokens SELECT policy

drop policy if exists "device_tokens_select_self_or_moderator" on public.device_tokens;

create policy "device_tokens_select_self_or_moderator" on public.device_tokens
for select
using (
  member_id = auth.uid()
  or public.current_user_role() in ('owner', 'admin', 'monitor', 'supervisor')
);
