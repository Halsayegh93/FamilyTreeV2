-- شجرة العائلة (النساء) — جدول منفصل تماماً عن profiles.
create table if not exists public.women_members (
  id uuid primary key default gen_random_uuid(),
  first_name text not null default '',
  full_name text not null default '',
  parent_id uuid references public.women_members(id) on delete set null,
  sort_order integer not null default 0,
  gender text not null default 'female',
  is_deceased boolean not null default false,
  birth_date date,
  death_date date,
  is_hidden_from_tree boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists women_members_parent_id_idx on public.women_members(parent_id);

alter table public.women_members enable row level security;

-- قراءة: أي مستخدم مسجّل دخول.
drop policy if exists women_members_select on public.women_members;
create policy women_members_select on public.women_members
  for select to authenticated using (true);

-- كتابة (إضافة/تعديل/حذف): الإدارة فقط (المالك/المدير/المراقب).
drop policy if exists women_members_write on public.women_members;
create policy women_members_write on public.women_members
  for all to authenticated
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('owner','admin','monitor')))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('owner','admin','monitor')));

-- الجذر «المحمدعلي».
insert into public.women_members (first_name, full_name, parent_id, sort_order)
select 'المحمدعلي', 'المحمدعلي', null, 0
where not exists (select 1 from public.women_members where parent_id is null and full_name = 'المحمدعلي');;
