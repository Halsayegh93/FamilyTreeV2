-- Store iOS push tokens per member for external notifications.

create table if not exists public.device_tokens (
  id bigint generated always as identity primary key,
  member_id uuid not null references public.profiles(id) on delete cascade,
  token text not null,
  platform text not null default 'ios',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create unique index if not exists idx_device_tokens_token_unique
  on public.device_tokens(token);

create unique index if not exists idx_device_tokens_member_token_unique
  on public.device_tokens(member_id, token);

alter table public.device_tokens enable row level security;

drop policy if exists "device_tokens_select_self_or_moderator" on public.device_tokens;
create policy "device_tokens_select_self_or_moderator" on public.device_tokens
for select
using (
  member_id = auth.uid()
  or public.current_user_role() in ('supervisor', 'admin')
);

drop policy if exists "device_tokens_insert_self" on public.device_tokens;
create policy "device_tokens_insert_self" on public.device_tokens
for insert
with check (member_id = auth.uid());

drop policy if exists "device_tokens_update_self" on public.device_tokens;
create policy "device_tokens_update_self" on public.device_tokens
for update
using (member_id = auth.uid())
with check (member_id = auth.uid());
