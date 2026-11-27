-- مطبَّق على الحي ٢٠٢٦-١١-٢٧ بعد تجربة begin…rollback
-- «ليسا مكرّرين» على السيرفر (موافقة المالك ٢٠٢٦-١١-٢٧): مشترك بين المالك والمدير ويبقى بعد تغيير الجهاز —
-- بدل التخزين المحلي (UserDefaults) في `AdminDuplicateDismissStore`.
-- group_key = توقيع المجموعة في التطبيق (`AdminDuplicateNames.Group.signature`): «<الأب>|<المعرّفات مرتّبة بفواصل>»
-- بحروف صغيرة — إن انضمّ مكرّر جديد تغيّر المفتاح فتعود المجموعة.
-- القراءة والإضافة والحذف للمالك والمدير فقط (`current_user_role()` — الموقوف يفقدها)، بلا تعديل.
-- dismissed_by يُختم بمعرّف المتصل (لا يُكتب باسم غيره).
-- التراجع: supabase/rollback/20261127250000_duplicate_dismissals_rollback.sql
-- تجربة: cd supabase/tests/family_links && node duplicate_dismissals.test.mjs

create table if not exists public.duplicate_dismissals (
  group_key    text        primary key check (length(group_key) between 3 and 8000),
  dismissed_by uuid        default public.current_profile_id() references public.profiles(id) on delete set null,
  dismissed_at timestamptz not null default now()
);
comment on table public.duplicate_dismissals is
  '«ليسا مكرّرين» في «المكرر والأخطاء»: توقيع المجموعة (الأب|المعرّفات مرتّبة) — للمالك والمدير، مشترك بينهما.';

alter table public.duplicate_dismissals enable row level security;
revoke all on public.duplicate_dismissals from anon, authenticated;
grant select, insert, delete on public.duplicate_dismissals to authenticated;

drop policy if exists duplicate_dismissals_select on public.duplicate_dismissals;
create policy duplicate_dismissals_select on public.duplicate_dismissals
  for select to authenticated
  using (public.current_user_role() in ('owner', 'admin'));

drop policy if exists duplicate_dismissals_insert on public.duplicate_dismissals;
create policy duplicate_dismissals_insert on public.duplicate_dismissals
  for insert to authenticated
  with check (public.current_user_role() in ('owner', 'admin')
              and dismissed_by is not distinct from public.current_profile_id());

drop policy if exists duplicate_dismissals_delete on public.duplicate_dismissals;
create policy duplicate_dismissals_delete on public.duplicate_dismissals
  for delete to authenticated
  using (public.current_user_role() in ('owner', 'admin'));
