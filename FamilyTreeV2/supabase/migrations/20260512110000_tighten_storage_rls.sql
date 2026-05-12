-- 🔒 Tighten Storage RLS policies
--
-- المشكلة:
-- 1) policies "Give users authenticated access to folder 1oj01fe_0..3" تستخدم
--    `using (true)` / `with check (true)` — أي مستخدم مسجّل يقدر يحذف/يعدّل أي ملف
--    في أي bucket.
-- 2) policies "Auth Delete to gallery/news" + "Auth Insert/Update" مفتوحة لأي
--    مستخدم مسجّل بدون فحص ملكية الملف.
--
-- الإصلاح:
-- - حذف الـ policies المفتوحة
-- - استبدالها بـ policies تتحقق من ملكية الملف عبر مسار الملف (folder = user.id)
--   أو الصلاحية الإدارية.

-- =============================================
-- 1) حذف policies "Give users authenticated access" المفتوحة
-- =============================================
drop policy if exists "Give users authenticated access to folder 1oj01fe_0" on storage.objects;
drop policy if exists "Give users authenticated access to folder 1oj01fe_1" on storage.objects;
drop policy if exists "Give users authenticated access to folder 1oj01fe_2" on storage.objects;
drop policy if exists "Give users authenticated access to folder 1oj01fe_3" on storage.objects;

-- =============================================
-- 2) حذف policies gallery/news المفتوحة
-- =============================================
drop policy if exists "Auth Delete to gallery" on storage.objects;
drop policy if exists "Auth Delete to news" on storage.objects;
drop policy if exists "Auth Insert to gallery" on storage.objects;
drop policy if exists "Auth Insert to news" on storage.objects;
drop policy if exists "Auth Update to gallery" on storage.objects;
drop policy if exists "Auth Update to news" on storage.objects;

-- =============================================
-- 3) Gallery bucket — استبدال بـ policies آمنة
--    (member-gallery photos stored as `<member_id>/<filename>.jpg`)
-- =============================================

drop policy if exists "gallery_insert_own_or_admin" on storage.objects;
create policy "gallery_insert_own_or_admin" on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'gallery'
  and (
    auth.uid()::text = (storage.foldername(name))[1]
    or public.current_user_role() in ('owner', 'admin', 'monitor', 'supervisor')
  )
);

drop policy if exists "gallery_update_own_or_admin" on storage.objects;
create policy "gallery_update_own_or_admin" on storage.objects
for update
to authenticated
using (
  bucket_id = 'gallery'
  and (
    auth.uid()::text = (storage.foldername(name))[1]
    or public.current_user_role() in ('owner', 'admin', 'monitor', 'supervisor')
  )
);

drop policy if exists "gallery_delete_own_or_admin" on storage.objects;
create policy "gallery_delete_own_or_admin" on storage.objects
for delete
to authenticated
using (
  bucket_id = 'gallery'
  and (
    auth.uid()::text = (storage.foldername(name))[1]
    or public.current_user_role() in ('owner', 'admin', 'monitor', 'supervisor')
  )
);

-- =============================================
-- 4) News bucket — للأدمن فقط
-- =============================================

drop policy if exists "news_insert_admin" on storage.objects;
create policy "news_insert_admin" on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'news'
  and public.current_user_role() in ('owner', 'admin', 'monitor', 'supervisor')
);

drop policy if exists "news_update_admin" on storage.objects;
create policy "news_update_admin" on storage.objects
for update
to authenticated
using (
  bucket_id = 'news'
  and public.current_user_role() in ('owner', 'admin', 'monitor', 'supervisor')
);

drop policy if exists "news_delete_admin" on storage.objects;
create policy "news_delete_admin" on storage.objects
for delete
to authenticated
using (
  bucket_id = 'news'
  and public.current_user_role() in ('owner', 'admin', 'monitor', 'supervisor')
);

-- =============================================
-- 5) Avatars bucket — كل عضو يعدّل صورته الشخصية
--    (avatar files stored as `<user_id>.jpg` directly under bucket root)
-- =============================================

drop policy if exists "avatars_insert_own_or_admin" on storage.objects;
create policy "avatars_insert_own_or_admin" on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'avatars'
  and (
    -- الملف باسم <user_id>.jpg أو photo_suggestion_<user_id>_xxx.jpg
    auth.uid()::text = split_part(name, '.', 1)
    or name like ('photo_suggestion_' || auth.uid()::text || '_%')
    or public.current_user_role() in ('owner', 'admin', 'monitor', 'supervisor')
  )
);

drop policy if exists "avatars_update_own_or_admin" on storage.objects;
create policy "avatars_update_own_or_admin" on storage.objects
for update
to authenticated
using (
  bucket_id = 'avatars'
  and (
    auth.uid()::text = split_part(name, '.', 1)
    or name like ('photo_suggestion_' || auth.uid()::text || '_%')
    or public.current_user_role() in ('owner', 'admin', 'monitor', 'supervisor')
  )
);

drop policy if exists "avatars_delete_own_or_admin" on storage.objects;
create policy "avatars_delete_own_or_admin" on storage.objects
for delete
to authenticated
using (
  bucket_id = 'avatars'
  and (
    auth.uid()::text = split_part(name, '.', 1)
    or public.current_user_role() in ('owner', 'admin', 'monitor', 'supervisor')
  )
);

-- =============================================
-- 6) member-gallery bucket — العضو يدير ملفّاته (folder = member_id)
-- =============================================

drop policy if exists "member_gallery_insert_own_or_admin" on storage.objects;
create policy "member_gallery_insert_own_or_admin" on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'member-gallery'
  and (
    auth.uid()::text = (storage.foldername(name))[1]
    or public.current_user_role() in ('owner', 'admin', 'monitor', 'supervisor')
  )
);

drop policy if exists "member_gallery_update_own_or_admin" on storage.objects;
create policy "member_gallery_update_own_or_admin" on storage.objects
for update
to authenticated
using (
  bucket_id = 'member-gallery'
  and (
    auth.uid()::text = (storage.foldername(name))[1]
    or public.current_user_role() in ('owner', 'admin', 'monitor', 'supervisor')
  )
);

drop policy if exists "member_gallery_delete_own_or_admin" on storage.objects;
create policy "member_gallery_delete_own_or_admin" on storage.objects
for delete
to authenticated
using (
  bucket_id = 'member-gallery'
  and (
    auth.uid()::text = (storage.foldername(name))[1]
    or public.current_user_role() in ('owner', 'admin', 'monitor', 'supervisor')
  )
);

-- =============================================
-- 7) Public SELECT — مسموح للجميع (الصور تظهر بدون auth)
-- =============================================

drop policy if exists "Public Access to avatars" on storage.objects;
create policy "Public Access to avatars" on storage.objects
for select
to public
using (bucket_id = 'avatars');

drop policy if exists "Public Access to member-gallery" on storage.objects;
create policy "Public Access to member-gallery" on storage.objects
for select
to public
using (bucket_id = 'member-gallery');
