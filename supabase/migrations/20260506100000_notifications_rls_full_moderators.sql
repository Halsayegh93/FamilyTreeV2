-- Fix: include all moderator roles (owner, admin, monitor, supervisor) in notifications SELECT policy
-- Was: only supervisor + admin

drop policy if exists "notifications_select_target_or_all_or_moderator" on public.notifications;

create policy "notifications_select_target_or_all_or_moderator" on public.notifications
for select
using (
  target_member_id is null
  or target_member_id = auth.uid()
  or public.current_user_role() in ('owner', 'admin', 'monitor', 'supervisor')
);
