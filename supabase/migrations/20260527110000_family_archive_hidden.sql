-- ═══════════════════════════════════════════════════════════════════════════
-- إخفاء عناصر الأرشيف (soft hide) — بدون حذف
-- الإدارة (owner + admin) تقدر تخفي عنصر من اطلاع باقي الأعضاء، وترجع تُظهره لاحقاً
-- ═══════════════════════════════════════════════════════════════════════════

-- 1) عمود is_hidden — افتراضياً مرئي
alter table public.family_archive
  add column if not exists is_hidden boolean not null default false;

-- index على المرئي/المخفي لتسريع الفلترة
create index if not exists idx_family_archive_is_hidden
  on public.family_archive(is_hidden);

-- 2) تحديث RLS — non-admins يشوفون المرئي فقط، admins يشوفون الكل
drop policy if exists "family_archive_select_authenticated" on public.family_archive;
create policy "family_archive_select_authenticated" on public.family_archive
for select
using (
  auth.uid() is not null
  and (
    is_hidden = false
    or public.current_user_role() in ('owner', 'admin')
  )
);
