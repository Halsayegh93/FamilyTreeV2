-- سياسات بالهوية الموحّدة بدل profiles.id = auth.uid() (فحص ٢٠٢٦-١٠-٠٧، البند ن-٧ — موافقة المالك ٢٠٢٦-١٠-٠٧)
--
-- «Owner can update app_settings» كانت تشترط ملفاً معرّفه = auth.uid() ودوره owner:
--   • تنكسر إذا نُقل حساب المالك مرة أخرى (ربط app_metadata.profile_id — كما حدث ٢٤/٩)،
--   • وتتجاهل التجميد، وإذا لم تطابق صفاً يمرّ التحديث بلا خطأ فيرجع المفتاح بصمت.
-- بعد التعديل: current_user_role() = 'owner' (يقرأ current_profile_id() ويحترم الحالة) — للمالك
-- وحده كما كانت؛ المدير يبقى للقراءة.
--
-- ومن النمط نفسه في التقرير (الملكية بـ auth.uid() وحده):
--   • projects_update / projects_delete: صاحب المشروع = auth.uid() أو current_profile_id()
--     (إضافة فقط — من كان يملك يبقى يملك، والحساب المربوط بملف آخر يصل لمشاريعه). المالك
--     والمدير كما هما.
--   • avatars_* عولجت في 20261007120000 (نفس الإضافة).
--
-- التراجع: supabase/rollback/20261007150000_owner_policies_by_role_rollback.sql
-- التجربة: supabase/tests/family_links/audit_2026_10_07.test.mjs

drop policy if exists "Owner can update app_settings" on public.app_settings;
create policy "Owner can update app_settings" on public.app_settings
  for update to authenticated
  using (public.current_user_role() = 'owner')
  with check (public.current_user_role() = 'owner');

drop policy if exists projects_update on public.projects;
create policy projects_update on public.projects
  for update to authenticated
  using (owner_id = any (array[auth.uid(), public.current_profile_id()])
         or public.current_user_role() = any (array['owner', 'admin']))
  with check (owner_id = any (array[auth.uid(), public.current_profile_id()])
              or public.current_user_role() = any (array['owner', 'admin']));

drop policy if exists projects_delete on public.projects;
create policy projects_delete on public.projects
  for delete to authenticated
  using (owner_id = any (array[auth.uid(), public.current_profile_id()])
         or public.current_user_role() = any (array['owner', 'admin']));
