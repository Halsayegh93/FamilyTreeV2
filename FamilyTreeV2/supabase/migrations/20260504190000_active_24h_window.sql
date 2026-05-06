-- نافذة 24 ساعة بدل 30 دقيقة — الأعضاء ما يختفون

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
        else 'web'
      end
    ),
    e.eat,
    extract(epoch from (now() - e.eat))::int
  from effective_activity e
  where e.eat > now() - interval '24 hours'
  order by e.eat desc;
end;
$$;

grant execute on function public.get_active_members_now() to authenticated;
