-- ═══════════════════════════════════════════════════════════════════════════
-- إغلاق تحذير Supabase Advisor: "Clients can list all files in this bucket"
--
-- السياستان "Public Access to avatars" و "Public Access to member-gallery"
-- تمنحان SELECT واسعاً (to public) على storage.objects، فيستطيع أي عميل تنفيذ
-- list() وتعداد كل أسماء الملفات في الباكِت (= كل معرّفات الأعضاء) — تسريب أكثر
-- من المقصود.
--
-- الباكِتان عامّان (public) والتطبيق يعرض الصور عبر getPublicURL فقط (لا يستدعي
-- .list() في أي مكان)، والباكِت العام يخدم الملفات عبر مسار /object/public/ دون
-- الحاجة لسياسة SELECT. لذا حذف السياستين آمن: الصور تظل تظهر، لكن يُمنع التعداد.
-- ═══════════════════════════════════════════════════════════════════════════

drop policy if exists "Public Access to avatars" on storage.objects;
drop policy if exists "Public Access to member-gallery" on storage.objects;
