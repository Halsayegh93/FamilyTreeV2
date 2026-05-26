-- ═══════════════════════════════════════════════════════════════════════════
-- أرشيف العائلة — وثائق وكتب وصور قديمة قابلة للتنزيل
-- الصلاحيات: الكل يقرأ ويُحمّل، فقط owner + admin يرفع/يحذف
-- ═══════════════════════════════════════════════════════════════════════════

-- 1) الجدول
create table if not exists public.family_archive (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  category text not null check (category in ('documents', 'books', 'old_photos', 'other')),
  file_url text not null,
  file_type text not null,        -- MIME (مثل application/pdf, image/jpeg)
  file_size bigint,                -- بالبايت
  file_name text,                  -- الاسم الأصلي — للتنزيل
  thumbnail_url text,              -- مصغّرة اختيارية
  uploaded_by uuid not null references public.profiles(id) on delete set null,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_family_archive_category_created
  on public.family_archive(category, created_at desc);

create index if not exists idx_family_archive_uploaded_by
  on public.family_archive(uploaded_by);

-- 2) RLS على الجدول
alter table public.family_archive enable row level security;

-- قراءة: أي مستخدم مسجَّل
drop policy if exists "family_archive_select_authenticated" on public.family_archive;
create policy "family_archive_select_authenticated" on public.family_archive
for select
using (auth.uid() is not null);

-- إضافة: owner + admin فقط
drop policy if exists "family_archive_insert_owner_admin" on public.family_archive;
create policy "family_archive_insert_owner_admin" on public.family_archive
for insert
with check (
  public.current_user_role() in ('owner', 'admin')
  and uploaded_by = auth.uid()
);

-- تعديل: owner + admin فقط
drop policy if exists "family_archive_update_owner_admin" on public.family_archive;
create policy "family_archive_update_owner_admin" on public.family_archive
for update
using (public.current_user_role() in ('owner', 'admin'))
with check (public.current_user_role() in ('owner', 'admin'));

-- حذف: owner + admin فقط
drop policy if exists "family_archive_delete_owner_admin" on public.family_archive;
create policy "family_archive_delete_owner_admin" on public.family_archive
for delete
using (public.current_user_role() in ('owner', 'admin'));


-- ═══════════════════════════════════════════════════════════════════════════
-- 3) Storage bucket: family-archive
-- ═══════════════════════════════════════════════════════════════════════════
-- حد أقصى 100MB لكل ملف، PDF + صور
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'family-archive',
  'family-archive',
  true,
  104857600,  -- 100 MB
  array['application/pdf', 'image/jpeg', 'image/png', 'image/heic', 'image/webp']
)
on conflict (id) do update set
  file_size_limit    = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types,
  public             = excluded.public;

-- قراءة: أي مستخدم (bucket عام لكن نقيّد بـ auth)
drop policy if exists "family_archive_storage_read" on storage.objects;
create policy "family_archive_storage_read"
on storage.objects for select
using (bucket_id = 'family-archive');

-- رفع: owner + admin فقط
drop policy if exists "family_archive_storage_insert" on storage.objects;
create policy "family_archive_storage_insert"
on storage.objects for insert
with check (
  bucket_id = 'family-archive'
  and public.current_user_role() in ('owner', 'admin')
);

-- تعديل (لـ upsert إذا لزم): owner + admin
drop policy if exists "family_archive_storage_update" on storage.objects;
create policy "family_archive_storage_update"
on storage.objects for update
using (
  bucket_id = 'family-archive'
  and public.current_user_role() in ('owner', 'admin')
);

-- حذف: owner + admin فقط
drop policy if exists "family_archive_storage_delete" on storage.objects;
create policy "family_archive_storage_delete"
on storage.objects for delete
using (
  bucket_id = 'family-archive'
  and public.current_user_role() in ('owner', 'admin')
);
