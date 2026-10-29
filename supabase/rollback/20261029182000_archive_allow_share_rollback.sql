drop trigger if exists trg_family_archive_allow_share_guard on public.family_archive;
drop function if exists public.trg_family_archive_allow_share_guard();
alter table public.family_archive drop column if exists allow_share;
