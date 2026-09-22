-- رفع ملفات المكتبة: في مجلدات التصنيفات فقط (فحص الثغرات)
-- كان أي مستخدم مسجّل يرفع أي ملف لأي مسار في family-archive. التطبيقان يرفعان
-- إلى <التصنيف>/<uuid>.<ext> — التصنيفات المخصّصة تُرفع في other.
-- (جعل الـ bucket خاصاً — روابط موقّعة — مؤجّل للمرحلة الثانية مع حماية الأرقام،
--  لأن النسخ المثبّتة تستخدم الروابط العامة المخزّنة.)
drop policy if exists family_archive_storage_insert on storage.objects;
create policy family_archive_storage_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'family-archive'
    and auth.uid() is not null
    and (storage.foldername(name))[1] in ('documents', 'books', 'old_photos', 'other')
    and array_length(storage.foldername(name), 1) = 1
  );
