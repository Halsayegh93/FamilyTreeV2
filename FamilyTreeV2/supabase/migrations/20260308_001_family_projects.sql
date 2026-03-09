-- Family projects table

create table if not exists public.projects (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references public.profiles(id) on delete cascade,
    owner_name text not null,
    title text not null,
    description text,
    logo_url text,
    website_url text,
    instagram_url text,
    twitter_url text,
    tiktok_url text,
    snapchat_url text,
    whatsapp_number text,
    phone_number text,
    approval_status text not null default 'approved'
        check (approval_status in ('pending', 'approved', 'rejected')),
    approved_by uuid references public.profiles(id) on delete set null,
    created_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_projects_owner
    on public.projects(owner_id);

create index if not exists idx_projects_status_created
    on public.projects(approval_status, created_at desc);

alter table public.projects enable row level security;

-- All authenticated users can view approved projects
drop policy if exists "projects_select_authenticated" on public.projects;
create policy "projects_select_authenticated" on public.projects
for select
using (auth.uid() is not null);

-- Authenticated users can insert their own projects
drop policy if exists "projects_insert_self" on public.projects;
create policy "projects_insert_self" on public.projects
for insert
with check (owner_id = auth.uid());

-- Owner or moderator can update
drop policy if exists "projects_update_owner_or_mod" on public.projects;
create policy "projects_update_owner_or_mod" on public.projects
for update
using (
    owner_id = auth.uid()
    or public.current_user_role() in ('supervisor', 'admin')
);

-- Owner or moderator can delete
drop policy if exists "projects_delete_owner_or_mod" on public.projects;
create policy "projects_delete_owner_or_mod" on public.projects
for delete
using (
    owner_id = auth.uid()
    or public.current_user_role() in ('supervisor', 'admin')
);
