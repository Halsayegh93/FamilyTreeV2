-- ═══════════════════════════════════════════════════════════════════════════
-- معرض الصور — ألبومات (مسمّى + سنة اختيارية) كل ألبوم داخله صور
-- الصلاحيات: الكل يقرأ ويتصفّح، فقط owner + admin ينشئ/يرفع/يحذف
-- ═══════════════════════════════════════════════════════════════════════════

-- 1) جدول الألبومات
create table if not exists public.gallery_albums (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  year int,                        -- سنة الألبوم — اختيارية (للتجميع)
  cover_url text,                  -- غلاف مختار يدوياً — اختياري
  created_by uuid not null references public.profiles(id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  is_hidden boolean not null default false
);

create index if not exists idx_gallery_albums_year_created
  on public.gallery_albums(year desc nulls last, created_at desc);

-- 2) جدول الصور
create table if not exists public.gallery_photos (
  id uuid primary key default gen_random_uuid(),
  album_id uuid not null references public.gallery_albums(id) on delete cascade,
  photo_url text not null,
  caption text,
  sort_order int not null default 0,
  uploaded_by uuid not null references public.profiles(id) on delete set null,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_gallery_photos_album_sort
  on public.gallery_photos(album_id, sort_order asc, created_at asc);

-- ═══════════════════════════════════════════════════════════════════════════
-- 3) RLS — الألبومات
-- ═══════════════════════════════════════════════════════════════════════════
alter table public.gallery_albums enable row level security;

-- قراءة: أي مستخدم مسجَّل
drop policy if exists "gallery_albums_select_authenticated" on public.gallery_albums;
create policy "gallery_albums_select_authenticated" on public.gallery_albums
for select
using (auth.uid() is not null);

-- إضافة: owner + admin فقط
drop policy if exists "gallery_albums_insert_owner_admin" on public.gallery_albums;
create policy "gallery_albums_insert_owner_admin" on public.gallery_albums
for insert
with check (
  public.current_user_role() in ('owner', 'admin')
  and created_by = auth.uid()
);

-- تعديل: owner + admin فقط
drop policy if exists "gallery_albums_update_owner_admin" on public.gallery_albums;
create policy "gallery_albums_update_owner_admin" on public.gallery_albums
for update
using (public.current_user_role() in ('owner', 'admin'))
with check (public.current_user_role() in ('owner', 'admin'));

-- حذف: owner + admin فقط
drop policy if exists "gallery_albums_delete_owner_admin" on public.gallery_albums;
create policy "gallery_albums_delete_owner_admin" on public.gallery_albums
for delete
using (public.current_user_role() in ('owner', 'admin'));

-- ═══════════════════════════════════════════════════════════════════════════
-- 4) RLS — الصور
-- ═══════════════════════════════════════════════════════════════════════════
alter table public.gallery_photos enable row level security;

-- قراءة: أي مستخدم مسجَّل
drop policy if exists "gallery_photos_select_authenticated" on public.gallery_photos;
create policy "gallery_photos_select_authenticated" on public.gallery_photos
for select
using (auth.uid() is not null);

-- إضافة: owner + admin فقط
drop policy if exists "gallery_photos_insert_owner_admin" on public.gallery_photos;
create policy "gallery_photos_insert_owner_admin" on public.gallery_photos
for insert
with check (
  public.current_user_role() in ('owner', 'admin')
  and uploaded_by = auth.uid()
);

-- تعديل: owner + admin فقط
drop policy if exists "gallery_photos_update_owner_admin" on public.gallery_photos;
create policy "gallery_photos_update_owner_admin" on public.gallery_photos
for update
using (public.current_user_role() in ('owner', 'admin'))
with check (public.current_user_role() in ('owner', 'admin'));

-- حذف: owner + admin فقط
drop policy if exists "gallery_photos_delete_owner_admin" on public.gallery_photos;
create policy "gallery_photos_delete_owner_admin" on public.gallery_photos
for delete
using (public.current_user_role() in ('owner', 'admin'));

-- ═══════════════════════════════════════════════════════════════════════════
-- 5) Storage bucket: family-gallery
-- ═══════════════════════════════════════════════════════════════════════════
-- صور فقط، حد أقصى 25MB لكل صورة
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'family-gallery',
  'family-gallery',
  true,
  26214400,  -- 25 MB
  array['image/jpeg', 'image/png', 'image/heic', 'image/webp']
)
on conflict (id) do update set
  file_size_limit    = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types,
  public             = excluded.public;

-- قراءة: أي مستخدم (bucket عام)
drop policy if exists "family_gallery_storage_read" on storage.objects;
create policy "family_gallery_storage_read"
on storage.objects for select
using (bucket_id = 'family-gallery');

-- رفع: owner + admin فقط
drop policy if exists "family_gallery_storage_insert" on storage.objects;
create policy "family_gallery_storage_insert"
on storage.objects for insert
with check (
  bucket_id = 'family-gallery'
  and public.current_user_role() in ('owner', 'admin')
);

-- تعديل: owner + admin
drop policy if exists "family_gallery_storage_update" on storage.objects;
create policy "family_gallery_storage_update"
on storage.objects for update
using (
  bucket_id = 'family-gallery'
  and public.current_user_role() in ('owner', 'admin')
);

-- حذف: owner + admin فقط
drop policy if exists "family_gallery_storage_delete" on storage.objects;
create policy "family_gallery_storage_delete"
on storage.objects for delete
using (
  bucket_id = 'family-gallery'
  and public.current_user_role() in ('owner', 'admin')
);
