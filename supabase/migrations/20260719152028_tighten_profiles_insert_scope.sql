-- مُستخرَجة من سجل الإنتاج (supabase_migrations.schema_migrations)
-- كانت مطبَّقة على القاعدة لكن ملفها مفقود من المستودع.

-- إغلاق ثغرة الإضافة: العضو العادي كان يقدر يُدرج صفوفًا (member/pending) بأي father_id عبر API خام.
-- الجديد: العضو العادي يُدرج فقط (نفسه للتسجيل) أو (ابنه المباشر father_id=auth.uid())، وبدور member/pending فقط.
-- المدير/المراقب/المشرف: أي إضافة. هذا يطابق تمامًا تحقّق RPC add_family_child (is_moderator() OR p_parent_id=auth.uid()).

drop policy if exists "profiles_insert_safe" on public.profiles;
drop policy if exists "المستخدم يضيف بياناته" on public.profiles;

create policy "profiles_insert_guarded" on public.profiles
for insert to authenticated
with check (
  -- فريق الإدارة: أي إضافة
  current_user_role() = any (array['owner','admin','monitor','supervisor'])
  or (
    -- غير الإداريين: نفسه (تسجيل) أو ابنه المباشر فقط، وبدور غير مرفوع
    coalesce(role, 'pending') = any (array['pending','member'])
    and (id = auth.uid() or father_id = auth.uid())
  )
);;
