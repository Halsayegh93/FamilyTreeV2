-- إصلاحان صغيران (فحص الثغرات ٢٠٢٦-١٠-٠٤)
--
-- ١) حذف التعليقات: السياسة كانت (صاحب التعليق أو المشرف/المدير) — المالك ليس منها، فحذفه
--    لتعليقات غيره كان لا يحذف شيئاً والتطبيق يقول «تم». أُضيف المالك.
-- ٢) جداول نسخ الإشعارات القديمة: RLS مفعّل بلا سياسات (لا قراءة الآن)، لكن صلاحيات
--    anon/authenticated باقية — أي تعطيل خاطئ لـ RLS يكشف ٢٣ ألف إشعار. سُحبت الصلاحيات.
-- التراجع: supabase/rollback/20261004190000_comments_owner_delete_and_backup_grants_rollback.sql

alter policy "Users can delete their own comments or admins can delete any"
  on public.news_comments
  using ((auth.uid() = author_id)
         or (public.current_user_role() = any (array['supervisor'::text, 'admin'::text, 'owner'::text])));

revoke all on public.notifications_admin_backup_20260919  from anon, authenticated;
revoke all on public.notifications_member_backup_20260919 from anon, authenticated;
revoke all on public.notifications_backup_20261004        from anon, authenticated;
