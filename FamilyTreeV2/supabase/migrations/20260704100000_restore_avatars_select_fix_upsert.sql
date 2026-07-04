-- إصلاح: استبدال الصور الشخصية متوقف منذ تحصين 2026-06-19 في كل التطبيقات.
-- السبب: 20260619120000/130000 حذفتا كل سياسات SELECT على باكِت avatars،
-- والـ upsert (استبدال ملف موجود) في Supabase Storage يتطلب SELECT + UPDATE معاً
-- → أي كتابة فوق <uuid>.jpg موجود تفشل بـ 42501 (آخر رفع ناجح: 2026-06-16).
--
-- هذا الملف أيضاً:
-- 1) يحذف السياسات الفضفاضة المضافة من الداشبورد (avatars_authenticated_*)
--    التي كانت تسمح لأي عضو مسجّل بالكتابة/الحذف على صور جميع الأعضاء (ثغرة).
-- 2) يجعل مطابقة "ملفّي أنا" غير حساسة لحالة الأحرف — iOS يرفع UUID بأحرف كبيرة
--    بينما auth.uid()::text صغيرة، فكان بند الرفع الذاتي لا يعمل إطلاقاً.
-- 3) يغطي صور الغلاف cover_<uuid>.jpg التي لم يكن يغطيها أي بند ذاتي.

-- ═══════════════════════════════════════════════════════════════════
-- 1) دالة مساعدة: استخراج معرّف العضو من اسم ملف الأفاتار
--    تقبل '<uuid>.jpg' أو 'cover_<uuid>.jpg' بأي حالة أحرف، وترجع null لغير ذلك.
-- ═══════════════════════════════════════════════════════════════════
create or replace function public.avatar_target_id(object_name text)
returns uuid
language sql
immutable
as $$
  select case
    when lower(split_part(object_name, '.', 1))
         ~ '^(cover_)?[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then replace(lower(split_part(object_name, '.', 1)), 'cover_', '')::uuid
    else null
  end
$$;

-- ═══════════════════════════════════════════════════════════════════
-- 2) إعادة SELECT للمسجّلين فقط — يُعيد upsert للعمل.
--    لا يفتح شيئاً جديداً فعلياً: الباكِت public أصلاً للعرض عبر روابط /object/public/.
--    (تحذير advisory السابق كان عن SELECT للعموم/anon — يبقى محجوباً.)
-- ═══════════════════════════════════════════════════════════════════
drop policy if exists "avatars_select_authenticated" on storage.objects;
create policy "avatars_select_authenticated" on storage.objects
for select
to authenticated
using (bucket_id = 'avatars');

-- ═══════════════════════════════════════════════════════════════════
-- 3) حذف السياسات الفضفاضة (أُضيفت من الداشبورد كمحاولة إصلاح سابقة)
-- ═══════════════════════════════════════════════════════════════════
drop policy if exists "avatars_authenticated_insert" on storage.objects;
drop policy if exists "avatars_authenticated_update" on storage.objects;
drop policy if exists "avatars_authenticated_delete" on storage.objects;

-- ═══════════════════════════════════════════════════════════════════
-- 4) إعادة بناء سياسات الكتابة: الإدارة، أو صاحب الملف (شامل الغلاف)،
--    أو اقتراح صورة باسمه، أو أحد أبنائه/أحفاده (نسل المستدعي).
-- ═══════════════════════════════════════════════════════════════════
drop policy if exists "avatars_insert_own_or_admin" on storage.objects;
create policy "avatars_insert_own_or_admin" on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'avatars'
  and (
    public.current_user_role() in ('owner', 'admin', 'monitor', 'supervisor')
    or name like ('photo_suggestion_' || auth.uid()::text || '_%')
    or public.avatar_target_id(name) = auth.uid()
    or (
      public.avatar_target_id(name) is not null
      and public.is_descendant_of_caller(public.avatar_target_id(name))
    )
  )
);

drop policy if exists "avatars_update_own_or_admin" on storage.objects;
create policy "avatars_update_own_or_admin" on storage.objects
for update
to authenticated
using (
  bucket_id = 'avatars'
  and (
    public.current_user_role() in ('owner', 'admin', 'monitor', 'supervisor')
    or name like ('photo_suggestion_' || auth.uid()::text || '_%')
    or public.avatar_target_id(name) = auth.uid()
    or (
      public.avatar_target_id(name) is not null
      and public.is_descendant_of_caller(public.avatar_target_id(name))
    )
  )
)
with check (
  bucket_id = 'avatars'
  and (
    public.current_user_role() in ('owner', 'admin', 'monitor', 'supervisor')
    or name like ('photo_suggestion_' || auth.uid()::text || '_%')
    or public.avatar_target_id(name) = auth.uid()
    or (
      public.avatar_target_id(name) is not null
      and public.is_descendant_of_caller(public.avatar_target_id(name))
    )
  )
);

drop policy if exists "avatars_delete_own_or_admin" on storage.objects;
create policy "avatars_delete_own_or_admin" on storage.objects
for delete
to authenticated
using (
  bucket_id = 'avatars'
  and (
    public.current_user_role() in ('owner', 'admin', 'monitor', 'supervisor')
    or public.avatar_target_id(name) = auth.uid()
  )
);
