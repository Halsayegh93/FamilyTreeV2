-- تراجع: سياسة حذف التعليقات كما كانت (بلا المالك)، وإرجاع صلاحيات جداول النسخ القديمة
alter policy "Users can delete their own comments or admins can delete any"
  on public.news_comments
  using ((auth.uid() = author_id)
         or (public.current_user_role() = any (array['supervisor'::text, 'admin'::text])));

grant all on public.notifications_admin_backup_20260919  to anon, authenticated;
grant all on public.notifications_member_backup_20260919 to anon, authenticated;
