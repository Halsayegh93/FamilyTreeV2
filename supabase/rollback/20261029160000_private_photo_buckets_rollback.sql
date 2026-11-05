-- تراجع 20261029160000_private_photo_buckets (السياسات السابقة حرفياً). مستودع «brand» يبقى (لا يضر).
-- الأسرع (أمر واحد يكفي لعودة الروابط العامة):
update storage.buckets set public = true
 where id in ('avatars', 'family-archive', 'family-gallery', 'gallery', 'news', 'stories');

drop policy if exists photos_read_members on storage.objects;
create policy avatars_select_authenticated on storage.objects for select to authenticated using (bucket_id = 'avatars'::text);
create policy "Public Access to gallery" on storage.objects for select to authenticated using (bucket_id = 'gallery'::text);
create policy "Public Access to news" on storage.objects for select to authenticated using (bucket_id = 'news'::text);
create policy family_gallery_storage_read on storage.objects for select to authenticated using (bucket_id = 'family-gallery'::text);
