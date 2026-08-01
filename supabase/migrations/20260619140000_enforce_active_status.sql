-- ═══════════════════════════════════════════════════════════════════════════
-- تحصين: فرض حالة الحساب (status) في RLS — 2026-06-19
--
-- المشكلة: current_user_role() يرجّع الدور بغضّ النظر عن status. فالعضو المجمّد
-- (status='frozen', role لا يزال 'member'/'admin'…) يبقى توكنه صالحاً ويمرّ كل
-- فحوص الدور في السياسات → يقدر يقرأ/يكتب رغم التجميد (الواجهة فقط تمنعه).
--
-- الحل (جراحي، يغطّي كل السياسات دفعة واحدة دون تعديلها): نجعل current_user_role()
-- يُرجِع 'frozen' للمجمّد، فتفشل كل فحوص `current_user_role() in (...)` تلقائياً.
-- المستخدم النشط لا يتأثر؛ المعلّق (role='pending') محجوب أصلاً.
-- الوصول للذات (id = auth.uid()) يبقى — لا يضرّ.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.current_user_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when p.status = 'frozen' then 'frozen'
    else p.role
  end
  from public.profiles p
  where p.id = coalesce(
    nullif(auth.jwt() -> 'user_metadata' ->> 'profile_id', '')::uuid,
    auth.uid()
  )
$$;

-- منع المجمّد من تعديل فرعه (الأبناء/الأحفاد) أيضاً — is_descendant_of_caller
-- لا يفحص الحالة. نضيف شرط أن يكون المستدعي نشطاً.
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
    (select status = 'active' from public.profiles where id = auth.uid()),
    false
  )
  and coalesce(
    (select exists (select 1 from ancestors where ancestor_id = auth.uid())),
    false
  );
$$;
