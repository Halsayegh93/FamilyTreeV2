-- ⚠️ مُعَدّ — لا يُطبَّق قبل تحديث التطبيقات الثلاثة (قرار المالك ٢٠٢٦-١٠-٢٩). جرّبه أولاً داخل begin; … rollback;
-- إقفال قراءة profiles المباشرة: العضو العادي يقرأ صفّه وصفوف من يحق له تعديلهم فقط؛ الباقي عبر members_masked
-- (واجهة يملكها postgres بلا security_invoker → تبقى تعمل بعد الإقفال وتخفي الرقم/الميلاد/الصورة/النشاط).
--
-- لماذا ليس «النفس أو الإدارة» فقط: Postgres يطبّق سياسة SELECT على UPDATE/DELETE التي فيها WHERE وعلى RETURNING،
-- فالعضو الذي يعدّل أبناءه/أحفاده (profiles_update_self_or_moderator: is_descendant_of_caller) أو يضيف ابناً
-- ثم .select() كان سيفشل. لذلك السياسة = نفس صفوف سياسة التعديل.
--
-- قبل التطبيق (المطلوب من التطبيقات — القائمة الكاملة في تقرير وكيل السيرفر ٢٠٢٦-١٠-٢٩):
--   • الموقع: tree/page.tsx:37، home/page.tsx:29 (العدّاد)، profile/page.tsx:40 و:48، projects/AddProjectButton.tsx:81،
--     lib/occasions/family-data.ts:140 → members_masked؛ register/page.tsx:73 و:92 وreset-password/page.tsx:75
--     تحتاج RPC (تعمل قبل الدخول/للمعلّق ولا تكفيها الواجهة).
--   • الأندرويد: member_details_screen.dart:621 (bio_json لعضو آخر) → members_masked.
--   • الاشتراك اللحظي على profiles (iOS RealtimeManager.swift:43/120، Android realtime.dart:36-51) لن يوصل للعضو
--     إلا تغييرات صفّه ومن تحته → يُحوَّل لقناة broadcast أو مؤقّت تحديث.
--   • embed «profiles(...)» في الموقع للإدارة فقط (devices، branch-supervisors، branch-scope) — يبقى يعمل.
-- مخاطر السيرفر (فُحصت ٢٠٢٦-١٠-٢٩): الدوال التي تعمل بصلاحية المتصل وتقرأ profiles: approvals_notify (تُنادى من دوال
-- definer فقط)، login_attempt_profile_id (من دوال SMS للمالك — definer)، app_usage_count_since/app_usage_member_total
-- (تأكد أنها تُنادى من دوال definer فقط؛ لو ناداها التطبيق مباشرة ستعدّ صفاً واحداً)، trg_profiles_descendant_guard
-- (يقرأ NEW/OLD فقط). سياسات branch_supervisors تقرأ profiles للإدارة (ترى الكل) — سليمة. لا واجهة security_invoker تقرأ profiles.

begin;
drop policy if exists profiles_select_self_or_approved on public.profiles;
create policy profiles_select_self_team_or_editable on public.profiles for select to authenticated
using (
  id = (select auth.uid())
  or id = (select public.current_profile_id())
  or (select public.is_team(auth.uid()))
  or ((select public.current_user_role()) = 'supervisor' and public.is_in_supervisor_branch(id))
  or ((select public.is_approved_member()) and public.is_descendant_of_caller(id))
);
-- anon لا يقرأ profiles أبداً (require_authenticated_profiles يمنعه أصلاً؛ هذا للوضوح)
revoke select on public.profiles from anon;
commit;

-- ═══ التراجع (السياسة السابقة حرفياً) ═══
-- begin;
-- drop policy if exists profiles_select_self_team_or_editable on public.profiles;
-- create policy profiles_select_self_or_approved on public.profiles for select to authenticated
--   using ((id = auth.uid()) OR ( SELECT is_approved_member() AS is_approved_member));
-- grant select on public.profiles to anon;
-- commit;
