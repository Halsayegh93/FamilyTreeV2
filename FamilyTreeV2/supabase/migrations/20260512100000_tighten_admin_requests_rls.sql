-- Tighten admin_requests INSERT policy
--
-- المشكلة: الـ policy السابقة كانت `auth.uid() is not null` فقط — أي مستخدم
-- مسجّل يقدر يُنشئ طلب باسم غيره (يضع requester_id لمستخدم آخر) → potential abuse.
--
-- الإصلاح: لازم الـ requester_id يطابق auth.uid()، إلا إذا كان المُنشِئ
-- مدير/مالك/مراقب/مشرف (يقدر يُنشئ طلب على عضو آخر — مثل تسجيل عضو جديد بنيابة عنه).

drop policy if exists "admin_requests_insert_authenticated" on public.admin_requests;
drop policy if exists "admin_requests_insert_self_or_moderator" on public.admin_requests;

create policy "admin_requests_insert_self_or_moderator" on public.admin_requests
for insert
with check (
  auth.uid() is not null
  and (
    requester_id = auth.uid()
    or public.current_user_role() in ('supervisor', 'admin', 'owner', 'monitor')
  )
);
