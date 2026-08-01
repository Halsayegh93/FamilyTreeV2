-- إصلاح:
-- 1. column reference "member_id" is ambiguous (تعارض OUT params مع جداول)
-- 2. column n.title does not exist (في جدول news ما عنده title)

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
        coalesce((select max(updated_at) from public.device_tokens where device_tokens.member_id = p.id), '1970-01-01'::timestamptz),
        coalesce((select max(last_seen_at) from public.web_sessions where web_sessions.member_id = p.id), '1970-01-01'::timestamptz)
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
        when exists (select 1 from public.web_sessions ws where ws.member_id = e.eid and ws.last_seen_at > now() - interval '7 days') then 'web'
        when exists (select 1 from public.device_tokens dt where dt.member_id = e.eid) then 'app'
        else null
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
        when exists (select 1 from public.web_sessions ws where ws.member_id = e.eid and ws.last_seen_at > now() - interval '14 days') then 'web'
        when exists (select 1 from public.device_tokens dt where dt.member_id = e.eid) then 'app'
        else null
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

-- إصلاح get_recent_member_actions: شيل n.title (ما موجود في news)
create or replace function public.get_recent_member_actions(hours_back int default 24)
returns table (
  member_id uuid,
  full_name text,
  avatar_url text,
  action_kind text,
  action_label text,
  action_at timestamptz,
  source text,
  minutes_ago int
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  cutoff timestamptz := now() - (hours_back || ' hours')::interval;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  return query
  with all_actions as (
    select
      p.id as mid,
      p.full_name as fname,
      p.avatar_url as avurl,
      'screen_visit'::text as kind,
      coalesce(p.current_screen, 'home') as label,
      p.last_active_at as at_time,
      coalesce(p.current_screen_source, 'app') as src
    from public.profiles p
    where p.last_active_at is not null and p.last_active_at > cutoff

    union all
    select n.author_id, p.full_name, p.avatar_url, 'news_add'::text,
           left(coalesce(n.content, 'منشور'), 40),
           n.created_at, 'app'::text
    from public.news n
    join public.profiles p on p.id = n.author_id
    where n.created_at > cutoff

    union all
    select nc.author_id, p.full_name, p.avatar_url, 'news_comment'::text,
           left(coalesce(nc.content, 'تعليق'), 40),
           nc.created_at, 'app'::text
    from public.news_comments nc
    join public.profiles p on p.id = nc.author_id
    where nc.created_at > cutoff

    union all
    select nl.member_id, p.full_name, p.avatar_url, 'news_like'::text,
           'إعجاب على منشور'::text,
           nl.created_at, 'app'::text
    from public.news_likes nl
    join public.profiles p on p.id = nl.member_id
    where nl.created_at > cutoff

    union all
    select npv.member_id, p.full_name, p.avatar_url, 'poll_vote'::text,
           'تصويت في استطلاع'::text,
           npv.created_at, 'app'::text
    from public.news_poll_votes npv
    join public.profiles p on p.id = npv.member_id
    where npv.created_at > cutoff

    union all
    select ar.requester_id, p.full_name, p.avatar_url,
           ('request_' || ar.request_type)::text,
           coalesce(ar.details, ar.request_type, 'طلب')::text,
           ar.created_at, 'app'::text
    from public.admin_requests ar
    join public.profiles p on p.id = ar.requester_id
    where ar.created_at > cutoff

    union all
    select dt.member_id, p.full_name, p.avatar_url, 'device_active'::text,
           ('فتح التطبيق · ' || coalesce(dt.platform, 'ios'))::text,
           dt.updated_at, 'app'::text
    from public.device_tokens dt
    join public.profiles p on p.id = dt.member_id
    where dt.updated_at > cutoff

    union all
    select ws.member_id, p.full_name, p.avatar_url, 'web_session'::text,
           'دخول الموقع'::text,
           ws.last_seen_at, 'web'::text
    from public.web_sessions ws
    join public.profiles p on p.id = ws.member_id
    where ws.last_seen_at > cutoff
  )
  select distinct on (mid)
    mid,
    fname,
    avurl,
    kind,
    label,
    at_time,
    src,
    extract(epoch from (now() - at_time))::int / 60
  from all_actions
  order by mid, at_time desc;
end;
$$;

grant execute on function public.get_active_members_now() to authenticated;
grant execute on function public.get_recently_active_members(int) to authenticated;
grant execute on function public.get_recent_member_actions(int) to authenticated;
