-- استنتاج مصدر النشاط: إذا current_screen_source = null، شيك على device_tokens
-- العضو عنده token => app، ما عنده => web

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
      case when exists (select 1 from public.device_tokens dt where dt.member_id = p.id) then 'app' else 'web' end
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
      case when exists (select 1 from public.device_tokens dt where dt.member_id = p.id) then 'app' else 'web' end
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
