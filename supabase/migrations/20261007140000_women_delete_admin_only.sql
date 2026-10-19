-- الحذف من شجرة النساء للمالك والمدير فقط (فحص ٢٠٢٦-١٠-٠٧، البند م-٣ — موافقة المالك ٢٠٢٦-١٠-٠٧)
--
-- كانت سياسة women_members_write من نوع ALL للمالك والمدير والمراقب، فالمراقب يحذف سجلاً من شجرة
-- النساء — وجدول الأدوار يجعل الحذف (canDeleteMembers) للمالك والمدير وحدهما.
--
-- بعد التعديل تُفصل إلى ثلاث:
--   • الإضافة والتعديل: المالك والمدير والمراقب (كما هو — المراقب يحتفظ بالتعديل).
--   • الحذف: المالك والمدير فقط. حذف المراقب لا يمسّ أي صف (RLS يصفّيه بلا خطأ).
-- الدوال لا تتغيّر: move_child_gender (تحويل ابن↔بنت = تعديل، الصف ينتقل للجدول الآخر)،
-- remove_self_wife / remove_self_woman_child (العضو يزيل زوجته/بنته هو)، ومزامنة profiles.
--
-- التراجع: supabase/rollback/20261007140000_women_delete_admin_only_rollback.sql
-- التجربة: supabase/tests/family_links/audit_2026_10_07.test.mjs

drop policy if exists women_members_write on public.women_members;
drop policy if exists women_members_insert on public.women_members;
drop policy if exists women_members_update on public.women_members;
drop policy if exists women_members_delete on public.women_members;

create policy women_members_insert on public.women_members
  for insert to authenticated
  with check (public.current_user_role() = any (array['owner', 'admin', 'monitor']));

create policy women_members_update on public.women_members
  for update to authenticated
  using (public.current_user_role() = any (array['owner', 'admin', 'monitor']))
  with check (public.current_user_role() = any (array['owner', 'admin', 'monitor']));

create policy women_members_delete on public.women_members
  for delete to authenticated
  using (public.current_user_role() = any (array['owner', 'admin']));
