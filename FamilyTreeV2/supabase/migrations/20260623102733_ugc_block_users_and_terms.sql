-- (1) حظر المستخدمين — كل مستخدم يحظر آخرين (Guideline 1.2).
create table if not exists public.blocked_users (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id)
);

alter table public.blocked_users enable row level security;

-- المستخدم يدير حظره فقط.
drop policy if exists blocked_users_select on public.blocked_users;
create policy blocked_users_select on public.blocked_users
  for select to authenticated using (blocker_id = auth.uid());

drop policy if exists blocked_users_insert on public.blocked_users;
create policy blocked_users_insert on public.blocked_users
  for insert to authenticated with check (blocker_id = auth.uid());

drop policy if exists blocked_users_delete on public.blocked_users;
create policy blocked_users_delete on public.blocked_users
  for delete to authenticated using (blocker_id = auth.uid());

-- (2) قبول شروط الاستخدام (EULA) — Guideline 1.2.
alter table public.profiles
  add column if not exists terms_accepted_at timestamptz;

comment on column public.profiles.terms_accepted_at is 'وقت موافقة العضو على شروط الاستخدام (EULA) — مطلوب لمحتوى المستخدمين';;
