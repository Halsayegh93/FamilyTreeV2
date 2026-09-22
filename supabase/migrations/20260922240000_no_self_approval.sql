-- لا يعالج المسؤول طلبه هو (فحص الثغرات)
-- المراقب/المدير كان يقدر يوافق على طلب تغيير اسمه أو رقمه بنفسه فيتجاوز حد
-- التعديلات. طلبك أنت يعالجه غيرك — إلا المالك (يعدّل ملفه مباشرة أصلاً).
drop policy if exists admin_requests_update_by_scope on public.admin_requests;
create policy admin_requests_update_by_scope on public.admin_requests for update to authenticated
  using (
    public.can_handle_admin_request(request_type)
    and (public.current_user_role() = 'owner'
         or (requester_id is distinct from auth.uid() and member_id is distinct from auth.uid()))
  )
  with check (public.can_handle_admin_request(request_type));
