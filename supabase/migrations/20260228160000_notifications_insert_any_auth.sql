-- السماح لأي مستخدم مسجل بإدراج إشعارات (ليس فقط المدراء)
-- مطلوب حتى يتمكن الأعضاء العاديون من إرسال إشعارات للمدراء عند تنفيذ إجراءات
drop policy if exists "notifications_insert_moderator" on public.notifications;
drop policy if exists "notifications_insert_authenticated" on public.notifications;
create policy "notifications_insert_authenticated" on public.notifications
for insert
with check (auth.uid() is not null);
