-- قفل الصور (قرار المالك ٢٠٢٦-١٠-٢٩ «اقفله الآن»): المستودعات الستة تصير خاصة، والقراءة بروابط موقّعة فقط
-- (الآيفون StorageURLResolver، الأندرويد storage_url.dart، الموقع storage-url.ts — كلها توقّع وترجع للرابط العام احتياطاً).
-- • القراءة (= إنشاء رابط موقّع): العضو المعتمد والإدارة، وصاحب الملف، والمسجّل المعلّق صورته هو في avatars.
--   family-archive يبقى بسياسته الخاصة (المعتمد/ما رفعته/الإدارة). لا قراءة لغير المسجّلين.
-- • شعار البريد نُقل إلى مستودع عام صغير «brand» (email/family-logo-gold-v1.png) وحُدّثت دوال البريد الثلاث.
-- التراجع السريع بأمر واحد:
--   update storage.buckets set public = true where id in ('avatars','family-archive','family-gallery','gallery','news','stories');

drop policy if exists avatars_select_authenticated on storage.objects;
drop policy if exists "Public Access to gallery" on storage.objects;
drop policy if exists "Public Access to news" on storage.objects;
drop policy if exists family_gallery_storage_read on storage.objects;

create policy photos_read_members on storage.objects for select to authenticated
using (
  bucket_id in ('avatars', 'gallery', 'news', 'family-gallery', 'stories')
  and (
    (select public.is_approved_member())
    or (select public.is_team(auth.uid()))
    or owner_id = (select auth.uid())::text
    or (bucket_id = 'avatars'
        and public.avatar_target_id(name) = any (array[(select auth.uid()), (select public.current_profile_id())]))
  )
);

update storage.buckets set public = false
 where id in ('avatars', 'family-archive', 'family-gallery', 'gallery', 'news', 'stories');
