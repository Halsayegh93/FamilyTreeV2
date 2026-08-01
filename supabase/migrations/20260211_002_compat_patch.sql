-- Compatibility patch for projects running older schema versions.
-- Safe to run multiple times.

create extension if not exists "pgcrypto";

-- ===== notifications table (missing in older DBs) =====
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  target_member_id uuid null references public.profiles(id) on delete cascade,
  title text not null,
  body text not null,
  kind text not null default 'general',
  created_by uuid null references public.profiles(id) on delete set null,
  created_at timestamptz not null default timezone('utc', now())
);

-- ===== news columns backfill (older DBs may miss these) =====
alter table if exists public.news add column if not exists author_id uuid null references public.profiles(id) on delete cascade;
alter table if exists public.news add column if not exists author_name text;
alter table if exists public.news add column if not exists author_role text;
alter table if exists public.news add column if not exists role_color text default 'blue';
alter table if exists public.news add column if not exists content text;
alter table if exists public.news add column if not exists type text;
alter table if exists public.news add column if not exists image_url text;
alter table if exists public.news add column if not exists approval_status text;
alter table if exists public.news add column if not exists approved_by uuid null references public.profiles(id) on delete set null;
alter table if exists public.news add column if not exists approved_at timestamptz;
alter table if exists public.news add column if not exists created_at timestamptz;

update public.news
set approval_status = 'approved'
where approval_status is null;

update public.news
set role_color = 'blue'
where role_color is null or role_color = '';

update public.news
set created_at = timezone('utc', now())
where created_at is null;

alter table if exists public.news alter column approval_status set default 'pending';
alter table if exists public.news alter column role_color set default 'blue';
alter table if exists public.news alter column created_at set default timezone('utc', now());

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'news_approval_status_check'
  ) then
    alter table public.news
      add constraint news_approval_status_check
      check (approval_status in ('pending', 'approved', 'rejected'));
  end if;
end $$;

create index if not exists idx_news_status_created on public.news(approval_status, created_at desc);

-- ===== RLS policies for notifications =====
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
