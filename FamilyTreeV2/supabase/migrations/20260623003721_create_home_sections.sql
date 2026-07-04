-- أقسام رئيسية ديناميكية (server-driven) — يضيفها المدير وتظهر مع الوصول السريع.
create table if not exists public.home_sections (
  id uuid primary key default gen_random_uuid(),
  title text not null default '',
  subtitle text,
  icon text not null default 'link',     -- مفتاح أيقونة موحّد (link/info/star/...)
  color text not null default '#2B7A9F', -- hex
  type text not null default 'link' check (type in ('link','content')),
  url text,            -- لنوع link
  content_text text,   -- لنوع content
  image_url text,      -- لنوع content (اختياري)
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create index if not exists home_sections_active_idx on public.home_sections(is_active, sort_order);

alter table public.home_sections enable row level security;

drop policy if exists home_sections_select on public.home_sections;
create policy home_sections_select on public.home_sections
  for select to authenticated using (true);

drop policy if exists home_sections_write on public.home_sections;
create policy home_sections_write on public.home_sections
  for all to authenticated
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('owner','admin','monitor')))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('owner','admin','monitor')));;
