-- ==========================================================================
-- Web Sessions + Web Push Subscriptions
-- ==========================================================================
-- web_sessions: يسجل كل عضو استخدم الموقع (للتمييز عن مستخدمي التطبيق)
-- web_push_subscriptions: اشتراكات Push API للمتصفحات (إشعارات للمتصفح)

-- ── 1. web_sessions ────────────────────────────────────────────────────────
create table if not exists public.web_sessions (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.profiles(id) on delete cascade,
  user_agent text,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (member_id, user_agent)
);

create index if not exists web_sessions_member_id_idx on public.web_sessions(member_id);
create index if not exists web_sessions_last_seen_idx on public.web_sessions(last_seen_at desc);

alter table public.web_sessions enable row level security;

-- العضو يقدر يقرأ وينشئ جلسته فقط؛ المدراء يقدرون يقرون الكل
drop policy if exists "web_sessions_self_select" on public.web_sessions;
create policy "web_sessions_self_select" on public.web_sessions
  for select using (member_id = auth.uid());

drop policy if exists "web_sessions_admin_select" on public.web_sessions;
create policy "web_sessions_admin_select" on public.web_sessions
  for select using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role in ('owner','admin','monitor','supervisor')
    )
  );

drop policy if exists "web_sessions_self_upsert" on public.web_sessions;
create policy "web_sessions_self_upsert" on public.web_sessions
  for insert with check (member_id = auth.uid());

drop policy if exists "web_sessions_self_update" on public.web_sessions;
create policy "web_sessions_self_update" on public.web_sessions
  for update using (member_id = auth.uid());

-- RPC: يسجّل/يحدّث جلسة الموقع
create or replace function public.register_web_session(p_user_agent text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  insert into public.web_sessions (member_id, user_agent, last_seen_at)
  values (auth.uid(), p_user_agent, now())
  on conflict (member_id, user_agent)
  do update set last_seen_at = now();
end;
$$;

grant execute on function public.register_web_session(text) to authenticated;

-- ── 2. web_push_subscriptions ────────────────────────────────────────────
create table if not exists public.web_push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.profiles(id) on delete cascade,
  endpoint text not null,
  p256dh text not null,
  auth_key text not null,
  user_agent text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (endpoint)
);

create index if not exists web_push_subs_member_idx on public.web_push_subscriptions(member_id);

alter table public.web_push_subscriptions enable row level security;

drop policy if exists "web_push_subs_self_select" on public.web_push_subscriptions;
create policy "web_push_subs_self_select" on public.web_push_subscriptions
  for select using (member_id = auth.uid());

drop policy if exists "web_push_subs_admin_select" on public.web_push_subscriptions;
create policy "web_push_subs_admin_select" on public.web_push_subscriptions
  for select using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role in ('owner','admin','monitor','supervisor')
    )
  );

drop policy if exists "web_push_subs_self_upsert" on public.web_push_subscriptions;
create policy "web_push_subs_self_upsert" on public.web_push_subscriptions
  for insert with check (member_id = auth.uid());

drop policy if exists "web_push_subs_self_delete" on public.web_push_subscriptions;
create policy "web_push_subs_self_delete" on public.web_push_subscriptions
  for delete using (member_id = auth.uid());

-- RPC: يسجّل/يحدّث اشتراك push
create or replace function public.register_web_push_subscription(
  p_endpoint text,
  p_p256dh text,
  p_auth text,
  p_user_agent text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  insert into public.web_push_subscriptions (member_id, endpoint, p256dh, auth_key, user_agent, updated_at)
  values (auth.uid(), p_endpoint, p_p256dh, p_auth, p_user_agent, now())
  on conflict (endpoint)
  do update set
    member_id = auth.uid(),
    p256dh = excluded.p256dh,
    auth_key = excluded.auth_key,
    user_agent = excluded.user_agent,
    updated_at = now();
end;
$$;

grant execute on function public.register_web_push_subscription(text, text, text, text) to authenticated;

-- RPC: حذف اشتراك (عند unsubscribe من المتصفح)
create or replace function public.unregister_web_push_subscription(p_endpoint text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  delete from public.web_push_subscriptions
  where endpoint = p_endpoint
    and member_id = auth.uid();
end;
$$;

grant execute on function public.unregister_web_push_subscription(text) to authenticated;

-- ── 3. تحديث RPCs النشاط لاستخدام web_sessions ─────────────────────────
create or replace function public.get_active_members_now()
returns table (
  member_id uuid,
  full_name text,
  avatar_url text,
  current_screen text,
  current_screen_source text,
  last_active_at timestamptz,
  seconds_since_active int
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  return query
  select
    p.id,
    p.full_name,
    p.avatar_url,
    p.current_screen,
    coalesce(
      p.current_screen_source,
      case
        when exists (select 1 from public.web_sessions ws where ws.member_id = p.id and ws.last_seen_at > now() - interval '7 days') then 'web'
        when exists (select 1 from public.device_tokens dt where dt.member_id = p.id) then 'app'
        else null
      end
    ) as current_screen_source,
    p.last_active_at,
    extract(epoch from (now() - p.last_active_at))::int as seconds_since_active
  from public.profiles p
  where p.last_active_at > now() - interval '5 minutes'
  order by p.last_active_at desc;
end;
$$;

create or replace function public.get_recently_active_members(days_back int default 14)
returns table (
  member_id uuid,
  full_name text,
  avatar_url text,
  current_screen text,
  current_screen_source text,
  last_active_at timestamptz,
  hours_since_active int
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  return query
  select
    p.id,
    p.full_name,
    p.avatar_url,
    p.current_screen,
    coalesce(
      p.current_screen_source,
      case
        when exists (select 1 from public.web_sessions ws where ws.member_id = p.id and ws.last_seen_at > now() - interval '14 days') then 'web'
        when exists (select 1 from public.device_tokens dt where dt.member_id = p.id) then 'app'
        else null
      end
    ) as current_screen_source,
    p.last_active_at,
    extract(epoch from (now() - p.last_active_at))::int / 3600 as hours_since_active
  from public.profiles p
  where p.last_active_at is not null
    and p.last_active_at > now() - (days_back || ' days')::interval
  order by p.last_active_at desc;
end;
$$;

grant execute on function public.get_active_members_now() to authenticated;
grant execute on function public.get_recently_active_members(int) to authenticated;
