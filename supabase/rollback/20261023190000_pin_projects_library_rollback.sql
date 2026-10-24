-- تراجع 20261023190000: إزالة التثبيت من المشاريع والمكتبة
drop trigger if exists trg_projects_pinned_at_guard on public.projects;
drop trigger if exists trg_family_archive_pinned_at_guard on public.family_archive;
drop function if exists public.trg_pinned_at_admin_only();
alter table public.projects       drop column if exists pinned_at;
alter table public.family_archive drop column if exists pinned_at;
