-- ═══════════════════════════════════════════════════════════════════════════
-- موافقة على إضافات الأرشيف
-- - الكل يقدر يرفع، لكن الإضافة ما تظهر إلا بعد موافقة الإدارة
-- - رفع owner/admin يُوافق عليه تلقائياً (يضبطه التطبيق عند الـ INSERT)
-- ═══════════════════════════════════════════════════════════════════════════

-- 1) أعمدة الموافقة
alter table public.family_archive
  add column if not exists approval_status text not null default 'pending'
    check (approval_status in ('pending', 'approved', 'rejected'));

alter table public.family_archive
  add column if not exists approved_by uuid references public.profiles(id) on delete set null;

alter table public.family_archive
  add column if not exists approved_at timestamptz;

-- اعتبار العناصر القديمة "موافق عليها" (إن وُجدت قبل تطبيق هذا الـ migration)
update public.family_archive
set approval_status = 'approved'
where approval_status = 'pending'
  and approved_at is null
  and created_at < now() - interval '1 minute';

create index if not exists idx_family_archive_approval_status
  on public.family_archive(approval_status);


-- 2) تحديث SELECT policy:
--    - المرئي للعامة: approved + غير مخفي
--    - المدراء يشوفون الكل (للموافقة/الرفض/إدارة الإخفاء)
--    - الرافع يشوف عناصره (بأي حالة) ليعرف نتيجة الموافقة
drop policy if exists "family_archive_select_authenticated" on public.family_archive;
create policy "family_archive_select_authenticated" on public.family_archive
for select
using (
  auth.uid() is not null
  and (
    (approval_status = 'approved' and is_hidden = false)
    or public.current_user_role() in ('owner', 'admin')
    or uploaded_by = auth.uid()
  )
);


-- 3) INSERT يتيح للجميع (مع شرط uploaded_by = auth.uid())
drop policy if exists "family_archive_insert_owner_admin" on public.family_archive;
drop policy if exists "family_archive_insert_authenticated" on public.family_archive;
create policy "family_archive_insert_authenticated" on public.family_archive
for insert
with check (
  auth.uid() is not null
  and uploaded_by = auth.uid()
);

-- (UPDATE و DELETE يبقيان للـ owner+admin فقط من الـ migration السابقة)


-- 4) Storage: السماح للجميع برفع ملفات داخل bucket family-archive
--    (الـ approval policy فوق هي اللي تتحكم في الظهور)
drop policy if exists "family_archive_storage_insert" on storage.objects;
create policy "family_archive_storage_insert"
on storage.objects for insert
with check (
  bucket_id = 'family-archive'
  and auth.uid() is not null
);
