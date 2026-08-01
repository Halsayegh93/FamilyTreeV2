-- السماح للمستخدم بتحديث is_read على إشعاراته
drop policy if exists "notifications_update_own" on public.notifications;
create policy "notifications_update_own" on public.notifications
for update
using (
  target_member_id is null
  or target_member_id = auth.uid()
  or public.current_user_role() in ('supervisor', 'admin')
)
with check (
  target_member_id is null
  or target_member_id = auth.uid()
  or public.current_user_role() in ('supervisor', 'admin')
);

-- السماح للمستخدم بحذف إشعاراته أو المدير يحذف أي إشعار
drop policy if exists "notifications_delete_own_or_moderator" on public.notifications;
create policy "notifications_delete_own_or_moderator" on public.notifications
for delete
using (
  target_member_id = auth.uid()
  or public.current_user_role() in ('supervisor', 'admin')
);
