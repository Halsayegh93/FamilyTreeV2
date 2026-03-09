-- Add caption field to gallery photos
alter table public.member_gallery_photos
  add column if not exists caption text null;
-- Allow photo owner to update their own photos (e.g. edit caption)
drop policy if exists "member_gallery_update_self" on public.member_gallery_photos;
create policy "member_gallery_update_self" on public.member_gallery_photos
for update
using (member_id = auth.uid())
with check (member_id = auth.uid());

