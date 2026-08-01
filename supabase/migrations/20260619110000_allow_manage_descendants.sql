-- ═══════════════════════════════════════════════════════════════════════════
-- السماح للعضو العادي بإدارة فروعه (الأبناء/الأحفاد) — 2026-06-19
--
-- السياق: التطبيق يسمح للعضو بتعديل أبنائه وإضافة صورهم. هذا كان يعمل سابقاً
-- فقط بسبب سياسة profiles المتساهلة (USING true) التي حُذفت في
-- 20260619100000 (لإغلاق ثغرة "أي عضو يعدّل أي ملف"). كما أن رفع صورة الابن
-- كان محجوباً منذ 20260512 (سياسة avatars تتطلّب اسم الملف = uid المستخدم).
--
-- الحل: دالة تتحقق أن الهدف من نسل المستخدم (سلسلة father_id تصل لـ auth.uid())،
-- ونضيفها لسياسات profiles (UPDATE) و avatars (INSERT/UPDATE). فيقدر العضو
-- يدير فرعه فقط — لا يعدّل أعضاء غير مرتبطين به.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.is_descendant_of_caller(target uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  with recursive ancestors as (
    select father_id as ancestor_id
      from public.profiles
     where id = target
    union all
    select p.father_id
      from public.profiles p
      join ancestors a on p.id = a.ancestor_id
     where p.father_id is not null
  )
  select coalesce(
    (select exists (select 1 from ancestors where ancestor_id = auth.uid())),
    false
  );
$$;

revoke all on function public.is_descendant_of_caller(uuid) from anon;
grant execute on function public.is_descendant_of_caller(uuid) to authenticated;

-- profiles UPDATE: الذات أو مشرف أو من نسل المستخدم (فرعه)
drop policy if exists "profiles_update_self_or_moderator" on public.profiles;
create policy "profiles_update_self_or_moderator" on public.profiles
for update
using (
  id = auth.uid()
  or public.current_user_role() in ('owner', 'admin', 'monitor', 'supervisor')
  or public.is_descendant_of_caller(id)
)
with check (
  id = auth.uid()
  or public.current_user_role() in ('owner', 'admin', 'monitor', 'supervisor')
  or public.is_descendant_of_caller(id)
);
-- (الـ trigger trg_prevent_role_self_promotion يبقى يمنع تغيير الدور/الحالة)

-- avatars storage: السماح برفع/تحديث صورة عضو من نسل المستخدم أيضاً
-- (اسم الملف = <member_id>.jpg). نتحقق أن split_part يطابق UUID قبل التحويل.
drop policy if exists "avatars_insert_own_or_admin" on storage.objects;
create policy "avatars_insert_own_or_admin" on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'avatars'
  and (
    auth.uid()::text = split_part(name, '.', 1)
    or name like ('photo_suggestion_' || auth.uid()::text || '_%')
    or public.current_user_role() in ('owner', 'admin', 'monitor', 'supervisor')
    or (
      split_part(name, '.', 1) ~ '^[0-9a-fA-F-]{36}$'
      and public.is_descendant_of_caller(split_part(name, '.', 1)::uuid)
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
    auth.uid()::text = split_part(name, '.', 1)
    or name like ('photo_suggestion_' || auth.uid()::text || '_%')
    or public.current_user_role() in ('owner', 'admin', 'monitor', 'supervisor')
    or (
      split_part(name, '.', 1) ~ '^[0-9a-fA-F-]{36}$'
      and public.is_descendant_of_caller(split_part(name, '.', 1)::uuid)
    )
  )
);
