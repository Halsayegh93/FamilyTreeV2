-- ═══════════════════════════════════════════════════════════════════════════
-- إخفاء مشاريع العائلة (soft hide) — بدون حذف
-- الإدارة (owner + admin) تقدر تخفي مشروع من اطلاع باقي الأعضاء، وترجع تُظهره لاحقاً
-- (يطابق نمط family_archive.is_hidden)
-- ═══════════════════════════════════════════════════════════════════════════

-- 1) عمود is_hidden — افتراضياً مرئي
alter table public.projects
  add column if not exists is_hidden boolean not null default false;

-- index لتسريع الفلترة على المرئي/المخفي
create index if not exists idx_projects_is_hidden
  on public.projects(is_hidden);

-- 2) تحديث RLS — non-admins يشوفون المرئي فقط، admins يشوفون الكل
drop policy if exists "projects_select_authenticated" on public.projects;
create policy "projects_select_authenticated" on public.projects
for select
using (
  auth.uid() is not null
  and (
    is_hidden = false
    or public.current_user_role() in ('owner', 'admin')
  )
);
