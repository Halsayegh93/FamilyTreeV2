-- إضافة عمود current_screen لتتبع مكان نشاط العضو في التطبيق/الموقع
-- + دالة تحديث آمنة (يحدثها العضو لنفسه فقط)

alter table public.profiles
  add column if not exists current_screen text,
  add column if not exists current_screen_source text;
  -- current_screen_source: 'app' أو 'web'

create or replace function public.update_my_current_screen(
  p_screen text,
  p_source text default 'app'
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  update public.profiles
     set current_screen = p_screen,
         current_screen_source = p_source,
         last_active_at = now()
   where id = auth.uid();
end;
$$;

grant execute on function public.update_my_current_screen(text, text) to authenticated;

-- دالة لجلب الأعضاء النشطين حالياً (آخر 5 دقائق) مع مكان نشاطهم
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
    p.current_screen_source,
    p.last_active_at,
    extract(epoch from (now() - p.last_active_at))::int as seconds_since_active
  from public.profiles p
  where p.last_active_at > now() - interval '5 minutes'
  order by p.last_active_at desc;
end;
$$;

grant execute on function public.get_active_members_now() to authenticated;
