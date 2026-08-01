-- إذا ما عنده device_token → اعتبره web user (default)
-- بدل ما يطلع "نشط" بدون تحديد

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
#variable_conflict use_column
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  return query
  with effective_activity as (
    select
      p.id as eid,
      p.full_name as efname,
      p.avatar_url as eavatar,
      p.current_screen as escreen,
      p.current_screen_source as esrc,
      greatest(
        coalesce(p.last_active_at, '1970-01-01'::timestamptz),
        coalesce((select max(updated_at)   from public.device_tokens where device_tokens.member_id = p.id), '1970-01-01'::timestamptz),
        coalesce((select max(last_seen_at) from public.web_sessions  where web_sessions.member_id  = p.id), '1970-01-01'::timestamptz)
      ) as eat
    from public.profiles p
  )
  select
    e.eid,
    e.efname,
    e.eavatar,
    e.escreen,
    coalesce(
      e.esrc,
      case
        when exists (select 1 from public.web_sessions ws where ws.member_id = e.eid) then 'web'
        when exists (select 1 from public.device_tokens dt where dt.member_id = e.eid) then 'app'
        else 'web'   -- default: عضو بدون device_token غالباً ويب
      end
    ),
    e.eat,
    extract(epoch from (now() - e.eat))::int
  from effective_activity e
  where e.eat > now() - interval '5 minutes'
  order by e.eat desc;
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
#variable_conflict use_column
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  return query
  with effective_activity as (
    select
      p.id as eid,
      p.full_name as efname,
      p.avatar_url as eavatar,
      p.current_screen as escreen,
      p.current_screen_source as esrc,
      greatest(
        coalesce(p.last_active_at,                                                                        '1970-01-01'::timestamptz),
        coalesce((select max(updated_at)   from public.device_tokens   where device_tokens.member_id  = p.id), '1970-01-01'::timestamptz),
        coalesce((select max(last_seen_at) from public.web_sessions    where web_sessions.member_id   = p.id), '1970-01-01'::timestamptz),
        coalesce((select max(created_at)   from public.news            where news.author_id           = p.id), '1970-01-01'::timestamptz),
        coalesce((select max(created_at)   from public.news_comments   where news_comments.author_id  = p.id), '1970-01-01'::timestamptz),
        coalesce((select max(created_at)   from public.news_likes      where news_likes.member_id     = p.id), '1970-01-01'::timestamptz),
        coalesce((select max(created_at)   from public.news_poll_votes where news_poll_votes.member_id= p.id), '1970-01-01'::timestamptz),
        coalesce((select max(created_at)   from public.admin_requests  where admin_requests.requester_id = p.id), '1970-01-01'::timestamptz)
      ) as eat
    from public.profiles p
  )
  select
    e.eid,
    e.efname,
    e.eavatar,
    e.escreen,
    coalesce(
      e.esrc,
      case
        when exists (select 1 from public.web_sessions ws where ws.member_id = e.eid) then 'web'
        when exists (select 1 from public.device_tokens dt where dt.member_id = e.eid) then 'app'
        else 'web'   -- default
      end
    ),
    e.eat,
    (extract(epoch from (now() - e.eat))::int / 3600)
  from effective_activity e
  where e.eat > now() - (days_back || ' days')::interval
    and e.eat > '1970-01-02'::timestamptz
  order by e.eat desc;
end;
$$;

grant execute on function public.get_active_members_now() to authenticated;
grant execute on function public.get_recently_active_members(int) to authenticated;
