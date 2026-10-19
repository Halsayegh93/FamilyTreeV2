-- سياسات الإدارة بالهوية الموحّدة — بقية النمط القديم (فحص ٢٠٢٦-١٠-٠٧، البند ن-٧ — موافقة المالك ٢٠٢٦-١٠-٠٧)
--
-- بعد 20261007150000 بقيت خمس سياسات تقرأ الدور من profiles بشرط p.id = auth.uid()
-- (واثنتان معها app_metadata.profile_id من الـ JWT مباشرة):
--   • تتجاهل التجميد — المدير/المراقب/المشرف المجمّد يبقى يقرأ ويكتب،
--   • وتنكسر (الثلاث الأولى) إذا نُقل حساب الإداري لملف آخر (ربط app_metadata.profile_id).
-- بعد التعديل: current_user_role() (يقرأ current_profile_id() ويحترم الحالة) بالأدوار نفسها:
--   • home_sections_write          (ALL)    المالك · المدير · المراقب
--   • web_sessions_admin_select    (SELECT) المالك · المدير · المراقب · المشرف
--   • web_push_subs_admin_select   (SELECT) المالك · المدير · المراقب · المشرف
--   • web_relatives_select         (SELECT) المالك · المدير · المراقب · المشرف
--   • web_relatives_write          (ALL)    المالك · المدير · المراقب
-- الأدوار والأوامر والجمهور (public/authenticated) كما هي حرفياً — الفرق الوحيد: المجمّد يفقد
-- صلاحيته، والحساب المنقول يحتفظ بها.
--
-- التراجع: supabase/rollback/20261007160000_staff_policies_by_role_rollback.sql
-- التجربة: supabase/tests/family_links/staff_policies_by_role.test.mjs

drop policy if exists home_sections_write on public.home_sections;
create policy home_sections_write on public.home_sections
  for all to authenticated
  using (public.current_user_role() = any (array['owner', 'admin', 'monitor']))
  with check (public.current_user_role() = any (array['owner', 'admin', 'monitor']));

drop policy if exists web_sessions_admin_select on public.web_sessions;
create policy web_sessions_admin_select on public.web_sessions
  for select to public
  using (public.current_user_role() = any (array['owner', 'admin', 'monitor', 'supervisor']));

drop policy if exists web_push_subs_admin_select on public.web_push_subscriptions;
create policy web_push_subs_admin_select on public.web_push_subscriptions
  for select to public
  using (public.current_user_role() = any (array['owner', 'admin', 'monitor', 'supervisor']));

drop policy if exists web_relatives_select on public.web_relatives;
create policy web_relatives_select on public.web_relatives
  for select to authenticated
  using (public.current_user_role() = any (array['owner', 'admin', 'monitor', 'supervisor']));

drop policy if exists web_relatives_write on public.web_relatives;
create policy web_relatives_write on public.web_relatives
  for all to authenticated
  using (public.current_user_role() = any (array['owner', 'admin', 'monitor']))
  with check (public.current_user_role() = any (array['owner', 'admin', 'monitor']));
