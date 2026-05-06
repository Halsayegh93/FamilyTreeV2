-- استخدام مصادر متعددة لاستنتاج "آخر نشاط" حتى لو last_active_at غير مُحدَّث
-- (مفيد لو المستخدم على نسخة قديمة من التطبيق ما تستدعي touch_last_active)

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
  with effective_activity as (
    select
      p.id,
      p.full_name,
      p.avatar_url,
      p.current_screen,
      p.current_screen_source,
      greatest(
        coalesce(p.last_active_at, '1970-01-01'::timestamptz),
        coalesce((select max(updated_at) from public.device_tokens where member_id = p.id), '1970-01-01'::timestamptz),
        coalesce((select max(last_seen_at) from public.web_sessions where member_id = p.id), '1970-01-01'::timestamptz)
      ) as effective_at
    from public.profiles p
  )
  select
    e.id,
    e.full_name,
    e.avatar_url,
    e.current_screen,
    coalesce(
      e.current_screen_source,
      case
        when exists (select 1 from public.web_sessions ws where ws.member_id = e.id and ws.last_seen_at > now() - interval '7 days') then 'web'
        when exists (select 1 from public.device_tokens dt where dt.member_id = e.id) then 'app'
        else null
      end
    ),
    e.effective_at,
    extract(epoch from (now() - e.effective_at))::int
  from effective_activity e
  where e.effective_at > now() - interval '5 minutes'
  order by e.effective_at desc;
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
  with effective_activity as (
    select
      p.id,
      p.full_name,
      p.avatar_url,
      p.current_screen,
      p.current_screen_source,
      greatest(
        coalesce(p.last_active_at,                                                          '1970-01-01'::timestamptz),
        coalesce((select max(updated_at)  from public.device_tokens   where member_id = p.id), '1970-01-01'::timestamptz),
        coalesce((select max(last_seen_at) from public.web_sessions    where member_id = p.id), '1970-01-01'::timestamptz),
        coalesce((select max(created_at)  from public.news             where author_id  = p.id), '1970-01-01'::timestamptz),
        coalesce((select max(created_at)  from public.news_comments    where author_id  = p.id), '1970-01-01'::timestamptz),
        coalesce((select max(created_at)  from public.news_likes       where member_id  = p.id), '1970-01-01'::timestamptz),
        coalesce((select max(created_at)  from public.news_poll_votes  where member_id  = p.id), '1970-01-01'::timestamptz),
        coalesce((select max(created_at)  from public.admin_requests   where requester_id = p.id), '1970-01-01'::timestamptz)
      ) as effective_at
    from public.profiles p
  )
  select
    e.id,
    e.full_name,
    e.avatar_url,
    e.current_screen,
    coalesce(
      e.current_screen_source,
      case
        when exists (select 1 from public.web_sessions ws where ws.member_id = e.id and ws.last_seen_at > now() - interval '14 days') then 'web'
        when exists (select 1 from public.device_tokens dt where dt.member_id = e.id) then 'app'
        else null
      end
    ),
    e.effective_at,
    (extract(epoch from (now() - e.effective_at))::int / 3600)
  from effective_activity e
  where e.effective_at > now() - (days_back || ' days')::interval
    and e.effective_at > '1970-01-02'::timestamptz   -- استثني اللي ما عندهم أي نشاط
  order by e.effective_at desc;
end;
$$;

grant execute on function public.get_active_members_now() to authenticated;
grant execute on function public.get_recently_active_members(int) to authenticated;
