-- «إعلانات عند فتح التطبيق» (طلب المالك ٢٠٢٦-١١-١٢، العينة launch-announcements): صورة يرفعها المالك/المدير تظهر
-- على طول كل ما يفتح العضو التطبيق (الآيفون والأندرويد) لين تخلص المدة (يوم، يومين، تاريخ)، وزرّ تحتها، وأكثر من
-- إعلان يطلعون واحد ورا الثاني. الصورة في مستودع `news` تحت `launch/` (رفع الإدارة مسموح أصلاً، والقراءة موقّعة).
-- الترتيب في التطبيقين: الإعلانات ← «ما الجديد» ← شاشة التحديث.
-- التراجع: supabase/rollback/20261112170000_launch_announcements_rollback.sql

create table if not exists public.launch_announcements (
  id           uuid primary key default gen_random_uuid(),
  image_path   text not null,                       -- news/launch/<…>.jpg (مسار داخل مستودع news)
  button_kind  text not null default 'none'
               check (button_kind in ('none', 'update', 'news', 'link')),
  button_title text,                                -- فارغ = نص الزر الافتراضي لنوعه
  button_url   text,                                -- لـ link فقط
  member_ids   uuid[],                              -- null = الكل؛ وإلا من اختيروا («دولة» أو «أعضاء» في المنشئ)
  starts_at    timestamptz not null default now(),
  ends_at      timestamptz not null,
  stopped_at   timestamptz,                         -- «إيقاف» قبل وقته
  created_by   uuid default public.current_profile_id(),
  created_at   timestamptz not null default now(),
  constraint launch_announcements_period check (ends_at > starts_at),
  constraint launch_announcements_link check (button_kind <> 'link' or coalesce(btrim(button_url), '') <> '')
);

create index if not exists launch_announcements_active_idx
  on public.launch_announcements (ends_at) where stopped_at is null;

alter table public.launch_announcements enable row level security;

-- العضو: الشغالة الموجّهة له فقط. المالك والمدير: الكل (قائمة «الإعلانات عند الفتح»)
drop policy if exists launch_announcements_select on public.launch_announcements;
create policy launch_announcements_select on public.launch_announcements
  for select to authenticated
  using (
    ((select public.current_user_role()) = any (array['owner', 'admin']))
    or (
      (select public.is_approved_member())
      and stopped_at is null
      and starts_at <= now() and ends_at > now()
      and (member_ids is null or (select public.current_profile_id()) = any (member_ids))
    )
  );

drop policy if exists launch_announcements_insert on public.launch_announcements;
create policy launch_announcements_insert on public.launch_announcements
  for insert to authenticated
  with check ((select public.current_user_role()) = any (array['owner', 'admin']));

drop policy if exists launch_announcements_update on public.launch_announcements;
create policy launch_announcements_update on public.launch_announcements
  for update to authenticated
  using ((select public.current_user_role()) = any (array['owner', 'admin']))
  with check ((select public.current_user_role()) = any (array['owner', 'admin']));

drop policy if exists launch_announcements_delete on public.launch_announcements;
create policy launch_announcements_delete on public.launch_announcements
  for delete to authenticated
  using ((select public.current_user_role()) = any (array['owner', 'admin']));

grant select, insert, update, delete on public.launch_announcements to authenticated;
revoke all on public.launch_announcements from anon;
