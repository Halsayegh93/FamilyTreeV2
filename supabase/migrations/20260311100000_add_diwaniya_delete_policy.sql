-- إضافة سياسة حذف الديوانيات: المالك أو المدير/المشرف
drop policy if exists "diwaniya_delete_owner_or_moderator" on public.diwaniyas;
create policy "diwaniya_delete_owner_or_moderator" on public.diwaniyas
for delete
using (
  owner_id = auth.uid()
  or public.current_user_role() in ('supervisor', 'admin')
);

-- إضافة سياسة تعديل للمالك (بالإضافة للمشرفين الحاليين)
drop policy if exists "diwaniya_update_owner" on public.diwaniyas;
create policy "diwaniya_update_owner" on public.diwaniyas
for update
using (owner_id = auth.uid())
with check (owner_id = auth.uid());
