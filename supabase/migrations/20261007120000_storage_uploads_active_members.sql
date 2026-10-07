-- رفع الملفات للأعضاء المفعّلين فقط + حدود الحجم والنوع لكل مستودع
-- (فحص ٢٠٢٦-١٠-٠٧، البند ع-١ — موافقة المالك ٢٠٢٦-١٠-٠٧)
--
-- كان أي حساب دخل برمز التحقق (ولو غريباً وصل شاشة التسجيل) يرفع أي ملف بأي نوع إلى مستودعات
-- عامة: «القصص» (أي مسار)، المكتبة (أربعة مجلّدات)، المعرض (مجلّده)، صور المشاريع.
--
-- بعد التعديل:
--   • «القصص» أُزيلت من التطبيق: تُحذف سياسة الرفع stories_auth_upload (القراءة والحذف باقيان
--     كما هما، والملفات الموجودة لا تُمسّ).
--   • كل رفع/استبدال يشترط عضواً مفعّلاً: current_user_role() ضمن (مالك، مدير، مراقب، مشرف، عضو)
--     — المعلّق والمجمّد والمحذوف ومن لا ملف له لا يرفعون.
--   • الاستثناء الوحيد: صورة المسجّل نفسه في avatars عند التسجيل (<معرّفه>.jpg) — الآيفون
--     والأندرويد يرفعانها بعد حفظ ملفه «معلّقاً» (AuthViewModel / registration_screen)، فتبقى
--     صورته هو فقط (avatar_target_id = هو) مسموحة للمعلّق.
--   • قواعد المسار لكل مستخدم باقية كما هي (مجلّده، photo_suggestion_<هو>_، project_photo_<هو>_،
--     project_logo_<هو>_، صورة ابنه)، ويُقبل معرّف ملفه current_profile_id() بجانب auth.uid()
--     (الحساب المربوط بـ app_metadata.profile_id — ن-٧).
--   • حدود المستودعات (يطبّقها خادم التخزين على كل رفع، ولا تمسّ الملفات الموجودة):
--       avatars / news / gallery / family-gallery: صور jpeg/png/heic/webp حتى ١٠ ميغابايت
--       (التطبيقات ترفع JPEG مضغوطاً؛ أكبر ملف موجود ٤٫٤ ميغابايت، والموقع يحدّ ٥).
--       family-archive (المكتبة): pdf + الصور نفسها حتى ٢٥ ميغابايت (كانت ١٠٠).
--   • news و family-gallery سياساتها أصلاً للإدارة عبر current_user_role() — لا تغيير.
--
-- التراجع: supabase/rollback/20261007120000_storage_uploads_active_members_rollback.sql
-- التجربة: supabase/tests/family_links/audit_2026_10_07.test.mjs

-- ─── «القصص»: لا رفع ───
drop policy if exists stories_auth_upload on storage.objects;

-- ─── المكتبة (family-archive): عضو مفعّل، والمجلّدات الأربعة كما هي ───
drop policy if exists family_archive_storage_insert on storage.objects;
create policy family_archive_storage_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'family-archive'
    and public.current_user_role() = any (array['owner', 'admin', 'monitor', 'supervisor', 'member'])
    and (storage.foldername(name))[1] = any (array['documents', 'books', 'old_photos', 'other'])
    and array_length(storage.foldername(name), 1) = 1
  );

-- ─── المعرض (gallery): الإدارة، أو العضو المفعّل في مجلّده ───
drop policy if exists gallery_insert_own_or_admin on storage.objects;
create policy gallery_insert_own_or_admin on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'gallery'
    and (
      public.current_user_role() = any (array['owner', 'admin', 'monitor', 'supervisor'])
      or (public.current_user_role() = 'member'
          and (storage.foldername(name))[1] = any (array[(auth.uid())::text, (public.current_profile_id())::text]))
    )
  );

drop policy if exists gallery_update_own_or_admin on storage.objects;
create policy gallery_update_own_or_admin on storage.objects
  for update to authenticated
  using (
    bucket_id = 'gallery'
    and (
      public.current_user_role() = any (array['owner', 'admin', 'monitor', 'supervisor'])
      or (public.current_user_role() = 'member'
          and (storage.foldername(name))[1] = any (array[(auth.uid())::text, (public.current_profile_id())::text]))
    )
  )
  with check (
    bucket_id = 'gallery'
    and (
      public.current_user_role() = any (array['owner', 'admin', 'monitor', 'supervisor'])
      or (public.current_user_role() = 'member'
          and (storage.foldername(name))[1] = any (array[(auth.uid())::text, (public.current_profile_id())::text]))
    )
  );

-- ─── معرض العضو (member-gallery — المستودع غير موجود اليوم؛ الأندرويد يرفع له) بالقاعدة نفسها ───
drop policy if exists member_gallery_insert_own_or_admin on storage.objects;
create policy member_gallery_insert_own_or_admin on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'member-gallery'
    and (
      public.current_user_role() = any (array['owner', 'admin', 'monitor', 'supervisor'])
      or (public.current_user_role() = 'member'
          and (storage.foldername(name))[1] = any (array[(auth.uid())::text, (public.current_profile_id())::text]))
    )
  );

drop policy if exists member_gallery_update_own_or_admin on storage.objects;
create policy member_gallery_update_own_or_admin on storage.objects
  for update to authenticated
  using (
    bucket_id = 'member-gallery'
    and (
      public.current_user_role() = any (array['owner', 'admin', 'monitor', 'supervisor'])
      or (public.current_user_role() = 'member'
          and (storage.foldername(name))[1] = any (array[(auth.uid())::text, (public.current_profile_id())::text]))
    )
  )
  with check (
    bucket_id = 'member-gallery'
    and (
      public.current_user_role() = any (array['owner', 'admin', 'monitor', 'supervisor'])
      or (public.current_user_role() = 'member'
          and (storage.foldername(name))[1] = any (array[(auth.uid())::text, (public.current_profile_id())::text]))
    )
  );

-- ─── الصور الشخصية (avatars) ───
-- الإدارة: أي ملف (صور الأعضاء، women_<id>، الأغلفة، اقتراحات الصور).
-- العضو المفعّل: صورته/غلافه، اقتراح صورة باسمه، صورة ابنه (is_descendant_of_caller).
-- المعلّق (التسجيل): صورته هو فقط.
drop policy if exists avatars_insert_own_or_admin on storage.objects;
create policy avatars_insert_own_or_admin on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (
      public.current_user_role() = any (array['owner', 'admin', 'monitor', 'supervisor'])
      or (public.current_user_role() = any (array['member', 'pending'])
          and public.avatar_target_id(name) = any (array[auth.uid(), public.current_profile_id()]))
      or (public.current_user_role() = 'member'
          and (name like ('photo_suggestion_' || (auth.uid())::text || '_%')
               or name like ('photo_suggestion_' || (public.current_profile_id())::text || '_%')
               or (public.avatar_target_id(name) is not null
                   and public.is_descendant_of_caller(public.avatar_target_id(name)))))
    )
  );

drop policy if exists avatars_update_own_or_admin on storage.objects;
create policy avatars_update_own_or_admin on storage.objects
  for update to authenticated
  using (
    bucket_id = 'avatars'
    and (
      public.current_user_role() = any (array['owner', 'admin', 'monitor', 'supervisor'])
      or (public.current_user_role() = any (array['member', 'pending'])
          and public.avatar_target_id(name) = any (array[auth.uid(), public.current_profile_id()]))
      or (public.current_user_role() = 'member'
          and (name like ('photo_suggestion_' || (auth.uid())::text || '_%')
               or name like ('photo_suggestion_' || (public.current_profile_id())::text || '_%')
               or (public.avatar_target_id(name) is not null
                   and public.is_descendant_of_caller(public.avatar_target_id(name)))))
    )
  )
  with check (
    bucket_id = 'avatars'
    and (
      public.current_user_role() = any (array['owner', 'admin', 'monitor', 'supervisor'])
      or (public.current_user_role() = any (array['member', 'pending'])
          and public.avatar_target_id(name) = any (array[auth.uid(), public.current_profile_id()]))
      or (public.current_user_role() = 'member'
          and (name like ('photo_suggestion_' || (auth.uid())::text || '_%')
               or name like ('photo_suggestion_' || (public.current_profile_id())::text || '_%')
               or (public.avatar_target_id(name) is not null
                   and public.is_descendant_of_caller(public.avatar_target_id(name)))))
    )
  );

-- صور المشاريع وشعاراتها (project_photo_<هو>_* / project_logo_<هو>_*): عضو مفعّل
drop policy if exists avatars_insert_project_photos on storage.objects;
create policy avatars_insert_project_photos on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and public.current_user_role() = any (array['owner', 'admin', 'monitor', 'supervisor', 'member'])
    and (
      name like ('project_photo_' || (auth.uid())::text || '_%')
      or name like ('project_logo_' || (auth.uid())::text || '_%')
      or name like ('project_photo_' || (public.current_profile_id())::text || '_%')
      or name like ('project_logo_' || (public.current_profile_id())::text || '_%')
    )
  );

-- ─── حدود الحجم والنوع ───
update storage.buckets
   set file_size_limit = 10485760,
       allowed_mime_types = array['image/jpeg', 'image/png', 'image/heic', 'image/webp']
 where id in ('avatars', 'news', 'gallery', 'family-gallery');

update storage.buckets
   set file_size_limit = 26214400,
       allowed_mime_types = array['application/pdf', 'image/jpeg', 'image/png', 'image/heic', 'image/webp']
 where id = 'family-archive';
