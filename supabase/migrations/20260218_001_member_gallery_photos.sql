-- Multi photos for member gallery

create table if not exists public.member_gallery_photos (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.profiles(id) on delete cascade,
  photo_url text not null,
  created_by uuid null references public.profiles(id) on delete set null,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_member_gallery_photos_member_created
  on public.member_gallery_photos(member_id, created_at desc);

alter table public.member_gallery_photos enable row level security;

drop policy if exists "member_gallery_select_authenticated" on public.member_gallery_photos;
create policy "member_gallery_select_authenticated" on public.member_gallery_photos
for select
using (auth.uid() is not null);

drop policy if exists "member_gallery_insert_self_or_moderator" on public.member_gallery_photos;
create policy "member_gallery_insert_self_or_moderator" on public.member_gallery_photos
for insert
with check (
  member_id = auth.uid()
  or public.current_user_role() in ('supervisor', 'admin')
);

drop policy if exists "member_gallery_delete_self_or_moderator" on public.member_gallery_photos;
create policy "member_gallery_delete_self_or_moderator" on public.member_gallery_photos
for delete
using (
  member_id = auth.uid()
  or public.current_user_role() in ('supervisor', 'admin')
);
