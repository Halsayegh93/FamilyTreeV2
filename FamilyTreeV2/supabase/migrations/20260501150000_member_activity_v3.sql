-- نشاط العضو v3:
-- - النافذة الزمنية: ١٤ يوم
-- - يُعتبر نشطاً إذا قام بأي فعل:
--     • تسجيل دخول (auth.users.last_sign_in_at)
--     • تجديد جلسة (auth.sessions.updated_at)
--     • تحديث جهاز (device_tokens.updated_at)
--     • نشر خبر، تعليق، إعجاب
--     • إضافة صورة معرض، إنشاء قصة
--     • إنشاء/تعديل ديوانية أو مشروع
--     • إرسال طلب إداري

drop function if exists public.get_members_activity(uuid[]);

create or replace function public.get_members_activity(member_ids uuid[])
returns table (
  member_id uuid,
  last_sign_in_at timestamptz,
  last_session_at timestamptz,
  last_device_active timestamptz,
  last_action_at timestamptz,
  is_active boolean,
  days_since_active int
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  threshold timestamptz := now() - interval '14 days';
begin
  if not (public.current_user_role() in ('owner', 'admin', 'monitor', 'supervisor')) then
    raise exception 'Permission denied: only moderators can query activity';
  end if;

  return query
  select
    p.id,
    au.last_sign_in_at,
    (select max(s.updated_at) from auth.sessions s where s.user_id = p.id) as last_session,
    (select max(dt.updated_at) from public.device_tokens dt where dt.member_id = p.id) as last_device,
    -- آخر فعل ضمن جداول التطبيق
    greatest(
      coalesce((select max(n.created_at) from public.news n where n.author_id = p.id), '1970-01-01'::timestamptz),
      coalesce((select max(nc.created_at) from public.news_comments nc where nc.member_id = p.id), '1970-01-01'::timestamptz),
      coalesce((select max(nl.created_at) from public.news_likes nl where nl.member_id = p.id), '1970-01-01'::timestamptz),
      coalesce((select max(npv.created_at) from public.news_poll_votes npv where npv.member_id = p.id), '1970-01-01'::timestamptz),
      coalesce((select max(g.created_at) from public.member_gallery_photos g where g.member_id = p.id), '1970-01-01'::timestamptz),
      coalesce((select max(d.created_at) from public.diwaniyas d where d.owner_id = p.id), '1970-01-01'::timestamptz),
      coalesce((select max(pr.created_at) from public.projects pr where pr.owner_id = p.id), '1970-01-01'::timestamptz),
      coalesce((select max(ar.created_at) from public.admin_requests ar where ar.requester_id = p.id), '1970-01-01'::timestamptz),
      coalesce((select max(fs.created_at) from public.family_stories fs where fs.member_id = p.id), '1970-01-01'::timestamptz)
    ) as last_action,
    -- نشط إذا أي إشارة من ٤ مصادر خلال ١٤ يوم
    case
      when au.last_sign_in_at > threshold then true
      when exists (select 1 from auth.sessions s where s.user_id = p.id and s.updated_at > threshold) then true
      when exists (select 1 from public.device_tokens dt where dt.member_id = p.id and dt.updated_at > threshold) then true
      when exists (select 1 from public.news n where n.author_id = p.id and n.created_at > threshold) then true
      when exists (select 1 from public.news_comments nc where nc.member_id = p.id and nc.created_at > threshold) then true
      when exists (select 1 from public.news_likes nl where nl.member_id = p.id and nl.created_at > threshold) then true
      when exists (select 1 from public.news_poll_votes npv where npv.member_id = p.id and npv.created_at > threshold) then true
      when exists (select 1 from public.member_gallery_photos g where g.member_id = p.id and g.created_at > threshold) then true
      when exists (select 1 from public.diwaniyas d where d.owner_id = p.id and d.created_at > threshold) then true
      when exists (select 1 from public.projects pr where pr.owner_id = p.id and pr.created_at > threshold) then true
      when exists (select 1 from public.admin_requests ar where ar.requester_id = p.id and ar.created_at > threshold) then true
      when exists (select 1 from public.family_stories fs where fs.member_id = p.id and fs.created_at > threshold) then true
      else false
    end as is_active,
    -- أيام منذ أحدث نشاط
    case
      when au.last_sign_in_at is null
        and not exists (select 1 from auth.sessions s where s.user_id = p.id)
      then null
      else extract(day from (now() - greatest(
        coalesce(au.last_sign_in_at, '1970-01-01'::timestamptz),
        coalesce((select max(s.updated_at) from auth.sessions s where s.user_id = p.id), '1970-01-01'::timestamptz)
      )))::int
    end as days_since_active
  from public.profiles p
  left join auth.users au on au.id = p.id
  where p.id = any(member_ids);
end;
$$;

grant execute on function public.get_members_activity(uuid[]) to authenticated;
