-- تراجع 20261007120000: سياسات الرفع وحدود المستودعات كما كانت على السيرفر الحي قبل ٢٠٢٦-١٠-٠٧
-- (منسوخة من pg_policies و storage.buckets حرفياً — تعيد الثغرة ع-١، للطوارئ فقط)

drop policy if exists stories_auth_upload on storage.objects;
create policy stories_auth_upload on storage.objects
  for insert to public
  with check ((bucket_id = 'stories'::text) AND (auth.uid() IS NOT NULL));

drop policy if exists family_archive_storage_insert on storage.objects;
create policy family_archive_storage_insert on storage.objects
  for insert to authenticated
  with check ((bucket_id = 'family-archive'::text) AND (auth.uid() IS NOT NULL)
    AND ((storage.foldername(name))[1] = ANY (ARRAY['documents'::text, 'books'::text, 'old_photos'::text, 'other'::text]))
    AND (array_length(storage.foldername(name), 1) = 1));

drop policy if exists gallery_insert_own_or_admin on storage.objects;
create policy gallery_insert_own_or_admin on storage.objects
  for insert to authenticated
  with check ((bucket_id = 'gallery'::text) AND (((auth.uid())::text = (storage.foldername(name))[1])
    OR (public.current_user_role() = ANY (ARRAY['owner'::text, 'admin'::text, 'monitor'::text, 'supervisor'::text]))));

drop policy if exists gallery_update_own_or_admin on storage.objects;
create policy gallery_update_own_or_admin on storage.objects
  for update to authenticated
  using ((bucket_id = 'gallery'::text) AND (((auth.uid())::text = (storage.foldername(name))[1])
    OR (public.current_user_role() = ANY (ARRAY['owner'::text, 'admin'::text, 'monitor'::text, 'supervisor'::text]))));

drop policy if exists member_gallery_insert_own_or_admin on storage.objects;
create policy member_gallery_insert_own_or_admin on storage.objects
  for insert to authenticated
  with check ((bucket_id = 'member-gallery'::text) AND (((auth.uid())::text = (storage.foldername(name))[1])
    OR (public.current_user_role() = ANY (ARRAY['owner'::text, 'admin'::text, 'monitor'::text, 'supervisor'::text]))));

drop policy if exists member_gallery_update_own_or_admin on storage.objects;
create policy member_gallery_update_own_or_admin on storage.objects
  for update to authenticated
  using ((bucket_id = 'member-gallery'::text) AND (((auth.uid())::text = (storage.foldername(name))[1])
    OR (public.current_user_role() = ANY (ARRAY['owner'::text, 'admin'::text, 'monitor'::text, 'supervisor'::text]))));

drop policy if exists avatars_insert_own_or_admin on storage.objects;
create policy avatars_insert_own_or_admin on storage.objects
  for insert to authenticated
  with check ((bucket_id = 'avatars'::text) AND ((public.current_user_role() = ANY (ARRAY['owner'::text, 'admin'::text, 'monitor'::text, 'supervisor'::text]))
    OR (name ~~ (('photo_suggestion_'::text || (auth.uid())::text) || '_%'::text))
    OR (public.avatar_target_id(name) = auth.uid())
    OR ((public.avatar_target_id(name) IS NOT NULL) AND public.is_descendant_of_caller(public.avatar_target_id(name)))));

drop policy if exists avatars_update_own_or_admin on storage.objects;
create policy avatars_update_own_or_admin on storage.objects
  for update to authenticated
  using ((bucket_id = 'avatars'::text) AND ((public.current_user_role() = ANY (ARRAY['owner'::text, 'admin'::text, 'monitor'::text, 'supervisor'::text]))
    OR (name ~~ (('photo_suggestion_'::text || (auth.uid())::text) || '_%'::text))
    OR (public.avatar_target_id(name) = auth.uid())
    OR ((public.avatar_target_id(name) IS NOT NULL) AND public.is_descendant_of_caller(public.avatar_target_id(name)))))
  with check ((bucket_id = 'avatars'::text) AND ((public.current_user_role() = ANY (ARRAY['owner'::text, 'admin'::text, 'monitor'::text, 'supervisor'::text]))
    OR (name ~~ (('photo_suggestion_'::text || (auth.uid())::text) || '_%'::text))
    OR (public.avatar_target_id(name) = auth.uid())
    OR ((public.avatar_target_id(name) IS NOT NULL) AND public.is_descendant_of_caller(public.avatar_target_id(name)))));

drop policy if exists avatars_insert_project_photos on storage.objects;
create policy avatars_insert_project_photos on storage.objects
  for insert to authenticated
  with check ((bucket_id = 'avatars'::text) AND ((name ~~ (('project_photo_'::text || (auth.uid())::text) || '_%'::text))
    OR (name ~~ (('project_logo_'::text || (auth.uid())::text) || '_%'::text))));

update storage.buckets set file_size_limit = null, allowed_mime_types = null where id in ('avatars', 'news', 'gallery');
update storage.buckets set file_size_limit = 26214400,
  allowed_mime_types = array['image/jpeg', 'image/png', 'image/heic', 'image/webp'] where id = 'family-gallery';
update storage.buckets set file_size_limit = 104857600,
  allowed_mime_types = array['application/pdf', 'image/jpeg', 'image/png', 'image/heic', 'image/webp'] where id = 'family-archive';
