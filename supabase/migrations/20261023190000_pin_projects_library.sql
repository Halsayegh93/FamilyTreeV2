-- تثبيت البطاقة في «المشاريع» و«المكتبة» (طلب المالك ٢٠٢٦-١٠-٢٣):
-- «في المشاريع و المكتبة ابى زر تثبيت البطاقة»
-- pinned_at = وقت التثبيت (null = غير مثبَّت). التطبيق يرتّب المثبَّتة أولاً
-- (الأحدث تثبيتاً أولاً) ثم الأحدث إضافة. التثبيت للمالك والمدير فقط، ويفرضه
-- السيرفر (لا الواجهة وحدها): أي تغيير لـ pinned_at من غيرهما يُرفض 42501.
-- النداءات بلا مستخدم (auth.uid() فارغ: مفتاح الخدمة، صيانة SQL) تمرّ.
-- لا تُطبَّق هذه الملف إلا بموافقة المالك. التراجع: supabase/rollback/20261023190000_pin_projects_library_rollback.sql

alter table public.projects       add column if not exists pinned_at timestamptz;
alter table public.family_archive add column if not exists pinned_at timestamptz;

create or replace function public.trg_pinned_at_admin_only()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if new.pinned_at is distinct from old.pinned_at
     and auth.uid() is not null
     and coalesce(public.current_user_role(), '') not in ('owner', 'admin') then
    raise exception 'pin_forbidden' using errcode = '42501',
      hint = 'التثبيت للمالك والمدير فقط';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_projects_pinned_at_guard on public.projects;
create trigger trg_projects_pinned_at_guard
  before update on public.projects
  for each row execute function public.trg_pinned_at_admin_only();

drop trigger if exists trg_family_archive_pinned_at_guard on public.family_archive;
create trigger trg_family_archive_pinned_at_guard
  before update on public.family_archive
  for each row execute function public.trg_pinned_at_admin_only();
