-- ═══════════════════════════════════════════════════════════════════════════
-- إغلاق نهائي لتحذير "Clients can list all files in this bucket".
-- حذف الاسم الثابت لم يكفِ لأن سياسات SELECT الحيّة على storage.objects قد تكون
-- أُنشئت من لوحة Supabase بأسماء مختلفة. هنا نحذف ديناميكياً أي سياسة SELECT على
-- storage.objects تخصّ باكِت avatars أو member-gallery (باكِتان عامّان يُخدمان عبر
-- public URL — لا يحتاجان SELECT). يبقى family-archive (المقيّد بـ authenticated)
-- وسياسات insert/update/delete دون مساس.
-- ═══════════════════════════════════════════════════════════════════════════

do $$
declare pol record;
begin
  for pol in
    select policyname
      from pg_policies
     where schemaname = 'storage'
       and tablename = 'objects'
       and cmd = 'SELECT'
       and (
         coalesce(qual, '') like '%avatars%'
         or coalesce(qual, '') like '%member-gallery%'
       )
  loop
    execute format('drop policy if exists %I on storage.objects', pol.policyname);
  end loop;
end $$;
