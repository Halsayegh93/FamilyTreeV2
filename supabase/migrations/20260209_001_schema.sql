-- FamilyTreeV2 MVP schema (Supabase)
create extension if not exists "pgcrypto";

-- ===== profiles =====
create table if not exists public.profiles (
  id uuid primary key,
  full_name text not null,
  first_name text not null,
  phone_number text,
  birth_date date,
  death_date date,
  is_deceased boolean not null default false,
  role text not null default 'pending' check (role in ('pending', 'member', 'supervisor', 'admin')),
  status text not null default 'pending' check (status in ('pending', 'active', 'frozen')),
  father_id uuid null references public.profiles(id) on delete set null,
  is_phone_hidden boolean not null default false,
  is_hidden_from_tree boolean not null default false,
  sort_order integer not null default 0,
  bio_json jsonb not null default '[]'::jsonb,
  avatar_url text,
  is_married boolean not null default false,
  created_at timestamptz not null default timezone('utc', now())
);

alter table public.profiles
  alter column id set default auth.uid();

-- ===== news =====
create table if not exists public.news (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles(id) on delete cascade,
  author_name text not null,
  author_role text not null,
  role_color text not null default 'blue',
  content text not null,
  type text not null,
  image_url text,
  approval_status text not null default 'pending' check (approval_status in ('pending', 'approved', 'rejected')),
  approved_by uuid null references public.profiles(id) on delete set null,
  approved_at timestamptz,
  created_at timestamptz not null default timezone('utc', now())
);

-- ===== admin requests =====
create table if not exists public.admin_requests (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.profiles(id) on delete cascade,
  requester_id uuid null references public.profiles(id) on delete set null,
  request_type text not null,
  new_value text,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  details text,
  created_at timestamptz not null default timezone('utc', now())
);

-- ===== diwaniyas =====
create table if not exists public.diwaniyas (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  owner_name text not null,
  title text not null,
  schedule_text text,
  contact_phone text,
  maps_url text,
  image_url text,
  approval_status text not null default 'pending' check (approval_status in ('pending', 'approved', 'rejected')),
  approved_by uuid null references public.profiles(id) on delete set null,
  approved_at timestamptz,
  created_at timestamptz not null default timezone('utc', now())
);

-- توافق مع قواعد بيانات قديمة قد تحتوي جدول diwaniyas بدون كل الأعمدة
alter table if exists public.diwaniyas add column if not exists owner_id uuid null references public.profiles(id) on delete cascade;
alter table if exists public.diwaniyas add column if not exists owner_name text;
alter table if exists public.diwaniyas add column if not exists title text;
alter table if exists public.diwaniyas add column if not exists schedule_text text;
alter table if exists public.diwaniyas add column if not exists contact_phone text;
alter table if exists public.diwaniyas add column if not exists maps_url text;
alter table if exists public.diwaniyas add column if not exists image_url text;
alter table if exists public.diwaniyas add column if not exists approval_status text;
alter table if exists public.diwaniyas add column if not exists approved_by uuid null references public.profiles(id) on delete set null;
alter table if exists public.diwaniyas add column if not exists approved_at timestamptz;
alter table if exists public.diwaniyas add column if not exists created_at timestamptz;

update public.diwaniyas
set approval_status = 'approved'
where approval_status is null;

update public.diwaniyas
set created_at = timezone('utc', now())
where created_at is null;

alter table if exists public.diwaniyas alter column approval_status set default 'pending';
alter table if exists public.diwaniyas alter column created_at set default timezone('utc', now());

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'diwaniyas_approval_status_check'
  ) then
    alter table public.diwaniyas
      add constraint diwaniyas_approval_status_check
      check (approval_status in ('pending', 'approved', 'rejected'));
  end if;
end $$;

-- ===== notifications =====
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  target_member_id uuid null references public.profiles(id) on delete cascade,
  title text not null,
  body text not null,
  kind text not null default 'general',
  created_by uuid null references public.profiles(id) on delete set null,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_profiles_father_id on public.profiles(father_id);
create index if not exists idx_profiles_role on public.profiles(role);
create index if not exists idx_news_status_created on public.news(approval_status, created_at desc);
create index if not exists idx_admin_requests_status on public.admin_requests(status, created_at desc);

-- ===== RLS =====
alter table public.profiles enable row level security;
alter table public.news enable row level security;
alter table public.admin_requests enable row level security;
alter table public.diwaniyas enable row level security;
alter table public.notifications enable row level security;

create or replace function public.current_user_role()
returns text
language sql
stable
as $$
  select p.role
  from public.profiles p
  where p.id = auth.uid()
$$;

-- profiles policies
drop policy if exists "profiles_select_authenticated" on public.profiles;
create policy "profiles_select_authenticated" on public.profiles
for select
using (auth.uid() is not null);

drop policy if exists "profiles_insert_self" on public.profiles;
create policy "profiles_insert_self" on public.profiles
for insert
with check (id = auth.uid());

drop policy if exists "profiles_update_self_or_moderator" on public.profiles;
create policy "profiles_update_self_or_moderator" on public.profiles
for update
using (
  id = auth.uid()
  or public.current_user_role() in ('supervisor', 'admin')
)
with check (
  id = auth.uid()
  or public.current_user_role() in ('supervisor', 'admin')
);

-- news policies
drop policy if exists "news_select_approved_or_owner_or_moderator" on public.news;
create policy "news_select_approved_or_owner_or_moderator" on public.news
for select
using (
  approval_status = 'approved'
  or author_id = auth.uid()
  or public.current_user_role() in ('supervisor', 'admin')
);

drop policy if exists "news_insert_authenticated" on public.news;
create policy "news_insert_authenticated" on public.news
for insert
with check (auth.uid() is not null and author_id = auth.uid());

drop policy if exists "news_update_moderator" on public.news;
create policy "news_update_moderator" on public.news
for update
using (public.current_user_role() in ('supervisor', 'admin'))
with check (public.current_user_role() in ('supervisor', 'admin'));

drop policy if exists "news_delete_owner_or_moderator" on public.news;
create policy "news_delete_owner_or_moderator" on public.news
for delete
using (author_id = auth.uid() or public.current_user_role() in ('supervisor', 'admin'));

-- admin request policies
drop policy if exists "admin_requests_select_moderator_or_owner" on public.admin_requests;
create policy "admin_requests_select_moderator_or_owner" on public.admin_requests
for select
using (
  requester_id = auth.uid()
  or member_id = auth.uid()
  or public.current_user_role() in ('supervisor', 'admin')
);

drop policy if exists "admin_requests_insert_authenticated" on public.admin_requests;
create policy "admin_requests_insert_authenticated" on public.admin_requests
for insert
with check (auth.uid() is not null);

drop policy if exists "admin_requests_update_moderator" on public.admin_requests;
create policy "admin_requests_update_moderator" on public.admin_requests
for update
using (public.current_user_role() in ('supervisor', 'admin'))
with check (public.current_user_role() in ('supervisor', 'admin'));

-- diwaniya policies
drop policy if exists "diwaniya_select_approved_or_owner_or_moderator" on public.diwaniyas;
create policy "diwaniya_select_approved_or_owner_or_moderator" on public.diwaniyas
for select
using (
  approval_status = 'approved'
  or owner_id = auth.uid()
  or public.current_user_role() in ('supervisor', 'admin')
);

drop policy if exists "diwaniya_insert_authenticated" on public.diwaniyas;
create policy "diwaniya_insert_authenticated" on public.diwaniyas
for insert
with check (auth.uid() is not null and owner_id = auth.uid());

drop policy if exists "diwaniya_update_moderator" on public.diwaniyas;
create policy "diwaniya_update_moderator" on public.diwaniyas
for update
using (public.current_user_role() in ('supervisor', 'admin'))
with check (public.current_user_role() in ('supervisor', 'admin'));

-- notifications policies
drop policy if exists "notifications_select_target_or_all_or_moderator" on public.notifications;
create policy "notifications_select_target_or_all_or_moderator" on public.notifications
for select
using (
  target_member_id is null
  or target_member_id = auth.uid()
  or public.current_user_role() in ('supervisor', 'admin')
);

drop policy if exists "notifications_insert_moderator" on public.notifications;
create policy "notifications_insert_moderator" on public.notifications
for insert
with check (public.current_user_role() in ('supervisor', 'admin'));
