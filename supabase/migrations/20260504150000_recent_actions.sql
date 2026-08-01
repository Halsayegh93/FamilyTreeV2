-- جلب آخر إجراءات الأعضاء خلال آخر N ساعة
-- يجمع من: شاشات / أخبار / تعليقات / إعجابات / تصويتات / طلبات / تسجيل أجهزة / جلسات ويب

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
declare
  cutoff timestamptz := now() - (hours_back || ' hours')::interval;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  return query
  with all_actions as (
    -- آخر شاشة تنقل لها
    select
      p.id as mid,
      p.full_name,
      p.avatar_url,
      'screen_visit'::text as kind,
      coalesce(p.current_screen, 'home') as label,
      p.last_active_at as at_time,
      coalesce(p.current_screen_source, 'app') as src
    from public.profiles p
    where p.last_active_at is not null and p.last_active_at > cutoff

    union all
    -- نشر خبر
    select n.author_id, p.full_name, p.avatar_url, 'news_add'::text,
           left(coalesce(n.content, n.title, 'منشور'), 40),
           n.created_at, 'app'::text
    from public.news n
    join public.profiles p on p.id = n.author_id
    where n.created_at > cutoff

    union all
    -- تعليق
    select nc.author_id, p.full_name, p.avatar_url, 'news_comment'::text,
           left(coalesce(nc.content, 'تعليق'), 40),
           nc.created_at, 'app'::text
    from public.news_comments nc
    join public.profiles p on p.id = nc.author_id
    where nc.created_at > cutoff

    union all
    -- إعجاب
    select nl.member_id, p.full_name, p.avatar_url, 'news_like'::text,
           'إعجاب على منشور'::text,
           nl.created_at, 'app'::text
    from public.news_likes nl
    join public.profiles p on p.id = nl.member_id
    where nl.created_at > cutoff

    union all
    -- تصويت في استطلاع
    select npv.member_id, p.full_name, p.avatar_url, 'poll_vote'::text,
           'تصويت في استطلاع'::text,
           npv.created_at, 'app'::text
    from public.news_poll_votes npv
    join public.profiles p on p.id = npv.member_id
    where npv.created_at > cutoff

    union all
    -- طلب إداري
    select ar.requester_id, p.full_name, p.avatar_url,
           ('request_' || ar.request_type)::text,
           coalesce(ar.details, ar.request_type, 'طلب')::text,
           ar.created_at, 'app'::text
    from public.admin_requests ar
    join public.profiles p on p.id = ar.requester_id
    where ar.created_at > cutoff

    union all
    -- تسجيل/تحديث جهاز (مفيد لنسخ التطبيق القديمة)
    select dt.member_id, p.full_name, p.avatar_url, 'device_active'::text,
           ('فتح التطبيق · ' || coalesce(dt.platform, 'ios'))::text,
           dt.updated_at, 'app'::text
    from public.device_tokens dt
    join public.profiles p on p.id = dt.member_id
    where dt.updated_at > cutoff

    union all
    -- جلسة ويب
    select ws.member_id, p.full_name, p.avatar_url, 'web_session'::text,
           'دخول الموقع'::text,
           ws.last_seen_at, 'web'::text
    from public.web_sessions ws
    join public.profiles p on p.id = ws.member_id
    where ws.last_seen_at > cutoff
  )
  select distinct on (mid)
    mid,
    full_name,
    avatar_url,
    kind,
    label,
    at_time,
    src,
    extract(epoch from (now() - at_time))::int / 60
  from all_actions
  order by mid, at_time desc;
end;
$$;

grant execute on function public.get_recent_member_actions(int) to authenticated;
