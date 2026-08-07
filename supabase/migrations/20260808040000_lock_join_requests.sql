-- إقفال جدول مهجور: join_requests تصميم قديم استبدله التدفّق الحيّ
-- (تسجيل → دور pending → موافقة الإدارة عبر admin_requests). الجدول فيه ٠ صف
-- ولا يعرفه أيٌّ من تطبيقات iOS/Flutter/الويب.
--
-- سياسته كانت متناقضة: تشترط تسجيل الدخول لجدول وظيفته استقبال طلبات ممّن
-- لا حساب له — فلا تخدم الزائر (ممنوع) ولا العضو (لا سبب لديه)، وتترك لأي
-- عضو إغراق الجدول بأسماء وأرقام مخترعة بلا عمود يدلّ على من أنشأها.
--
-- يوم تُبنى الميزة فعلاً، تصميمها يحدّد السياسة الصحيحة وتُفتح بسطر واحد.
drop policy if exists join_requests_insert_authenticated on public.join_requests;
create policy join_requests_insert_moderator on public.join_requests
for insert to authenticated
with check (
  public.current_user_role() = any (array['owner','admin','monitor','supervisor'])
);
