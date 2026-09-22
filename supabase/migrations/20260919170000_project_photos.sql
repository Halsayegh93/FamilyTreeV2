-- صور المشروع (طلب المالك 2026-09-19): معرض صور لكل مشروع.
--   1) عمود image_urls (قائمة روابط عامة) — إضافة فقط، لا يغيّر أي بيانات موجودة.
--   2) سماح للعضو برفع صور مشاريعه وشعارها إلى bucket الأفاتار باسم
--      project_photo_<auth.uid>_<uuid>.jpg أو project_logo_<auth.uid>_<uuid>.jpg فقط
--      (الإدارة مسموح لها أصلاً). كان العضو العادي لا يستطيع رفع الشعار إطلاقاً.
--
-- التراجع:
--   drop policy if exists avatars_insert_project_photos on storage.objects;
--   alter table public.projects drop column if exists image_urls;

alter table public.projects
  add column if not exists image_urls text[] not null default '{}';

drop policy if exists avatars_insert_project_photos on storage.objects;
create policy avatars_insert_project_photos on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (
      name like ('project_photo_' || auth.uid()::text || '_%')
      or name like ('project_logo_' || auth.uid()::text || '_%')
    )
  );
