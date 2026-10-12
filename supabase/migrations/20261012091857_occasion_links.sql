-- روابط عامة لمولّد «بوستات المناسبات» على الموقع (بدون تسجيل دخول).
-- المالك أو المدير ينشئ الرابط ويوقفه من لوحة الإدارة؛ الصفحة العامة تتحقق منه عبر دالة لا تكشف إلا true/false.
-- (مطبّقة على قاعدة البيانات بنفس رقم النسخة 20261012091857)
create table if not exists public.occasion_links (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9-]{6,64}$'),
  label text check (label is null or char_length(label) <= 80),
  is_active boolean not null default true,
  created_by uuid default public.current_profile_id() references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

alter table public.occasion_links enable row level security;

create policy occasion_links_admin_select on public.occasion_links
  for select to authenticated using (public.current_user_role() in ('owner', 'admin'));
create policy occasion_links_admin_insert on public.occasion_links
  for insert to authenticated with check (public.current_user_role() in ('owner', 'admin'));
create policy occasion_links_admin_update on public.occasion_links
  for update to authenticated
  using (public.current_user_role() in ('owner', 'admin'))
  with check (public.current_user_role() in ('owner', 'admin'));
create policy occasion_links_admin_delete on public.occasion_links
  for delete to authenticated using (public.current_user_role() in ('owner', 'admin'));

create or replace function public.occasion_link_is_active(p_slug text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.occasion_links where slug = lower(trim(p_slug)) and is_active);
$$;

revoke all on function public.occasion_link_is_active(text) from public;
grant execute on function public.occasion_link_is_active(text) to anon, authenticated;
