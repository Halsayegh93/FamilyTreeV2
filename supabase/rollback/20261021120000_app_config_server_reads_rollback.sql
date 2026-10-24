-- تراجع 20261021120000_app_config_server_reads: يعيد الدوال الست كما كانت في ترحيلاتها حرفياً (المصدر فوق كل واحدة)
-- فتعود الثوابت (٣٠ يوماً والنص، ٤٨ ساعة، ٥ في الساعة، ورد p_format ٣ = رد ٢). الصلاحيات كما هي.
-- طبّقه قبل تراجع 20261021110000_app_config. الدالة الطرفية send-sms-kwtsms الجديدة تبقى تعمل بعده (تأخذ رد ٢ ونصها المدمج).


-- ═══ ١) announce_death كما في 20261007130000 حرفياً ═══
create or replace function public.announce_death(p_member_id uuid, p_content text DEFAULT NULL::text, p_burial text DEFAULT NULL::text, p_notify boolean DEFAULT true)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_role     text := coalesce(public.current_user_role(), 'anonymous');
  v_caller   uuid := public.current_profile_id();
  v_tree     text := 'men';
  v_name     text;
  v_deceased boolean;
  v_female   boolean := false;
  v_verb     text;
  v_burial   text := nullif(btrim(coalesce(p_burial, '')), '');
  v_content  text;
  v_body     text;
  v_news_id  uuid;
  v_death    date;
  v_today    date := (now() at time zone 'Asia/Kuwait')::date;
begin
  if v_caller is null or v_role not in ('owner', 'admin') then
    raise exception 'announce_death: not allowed' using errcode = '42501';
  end if;

  select p.full_name, coalesce(p.is_deceased, false), coalesce(p.gender, '') = 'female', p.death_date
    into v_name, v_deceased, v_female, v_death
  from public.profiles p
  where p.id = p_member_id;

  if not found then
    v_tree := 'women';
    select w.full_name, w.is_deceased, coalesce(w.gender, 'female') = 'female', w.death_date
      into v_name, v_deceased, v_female, v_death
    from public.women_members w
    where w.id = p_member_id;
    if not found then
      raise exception 'announce_death: member not found' using errcode = 'P0002';
    end if;
  end if;

  if not coalesce(v_deceased, false) then
    raise exception 'announce_death: member is not deceased' using errcode = '22023';
  end if;

  if not (case
            when v_death is not null then v_death between v_today - 31 and v_today + 1
            else exists (select 1 from public.death_marks m
                         where m.member_id = p_member_id
                           and m.marked_at > now() - interval '30 days')
          end) then
    raise exception 'announce_death: death is not recent'
      using errcode = 'P0001', hint = 'death_not_recent';
  end if;

  insert into public.death_announcements (member_id, tree, announced_by)
  values (p_member_id, v_tree, v_caller)
  on conflict (member_id) do nothing;
  if not found then
    raise exception 'announce_death: already announced' using errcode = '23505';
  end if;

  v_name := btrim(coalesce(v_name, ''));
  v_verb := case when v_female then 'انتقلت إلى رحمة الله تعالى'
                 else 'انتقل إلى رحمة الله تعالى' end;

  v_content := coalesce(nullif(btrim(coalesce(p_content, '')), ''),
    v_verb || ' ' || v_name || E'\n'
    || case when v_female then 'تغمّدها الله بواسع رحمته وأسكنها فسيح جناته'
            else 'تغمّده الله بواسع رحمته وأسكنه فسيح جناته' end
    || E'\n' || 'إنا لله وإنا إليه راجعون');
  if v_burial is not null then
    v_content := v_content || E'\n\n' || 'الدفن: ' || v_burial;
  end if;

  insert into public.news
    (author_id, posted_by, author_name, author_role, role_color, content, type,
     image_urls, poll_options, approval_status, approved_by, approved_at)
  values
    (null, v_caller, 'إدارة العائلة', 'الإدارة',
     case v_role when 'owner' then 'gold' when 'admin' then 'purple' else 'green' end,
     v_content, 'وفاة', '[]'::jsonb, '[]'::jsonb,
     'approved', v_caller, timezone('utc', now()))
  returning id into v_news_id;

  update public.death_announcements
     set news_id = v_news_id
   where member_id = p_member_id;

  if p_notify then
    v_body := v_name || E'\n' || 'إنا لله وإنا إليه راجعون';
    if v_burial is not null then
      v_body := v_body || E'\n' || 'الدفن: ' || v_burial;
    end if;

    insert into public.notifications (target_member_id, title, body, kind, created_by, details)
    values (null, v_verb, v_body, 'admin_broadcast', v_caller,
            jsonb_build_object('type', 'death_announcement',
                               'member_id', p_member_id,
                               'tree', v_tree,
                               'news_id', v_news_id));
  end if;

  return v_news_id;
end;
$function$;

-- ═══ ٢) approvals_sla_tick وapprovals_report كما في 20261016120000 حرفياً ═══
create or replace function public.approvals_sla_tick()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  r       public.admin_requests%rowtype;
  sla_n   integer;
  esc_n   integer;
  sla_u   integer;
  esc_u   integer;
  sla     integer;
  esc     integer;
  hrs     numeric;
  h       text;
  label   text;
  about   text;
  where_  text;
  n_rem   integer := 0;
  n_esc   integer := 0;
begin
  if not public.approvals_workflow_on() then
    return jsonb_build_object('reminded', 0, 'escalated', 0, 'skipped', 'workflow_off');
  end if;
  select min(s.approvals_sla_hours), min(s.approvals_escalate_hours),
         min(s.approvals_urgent_sla_hours), min(s.approvals_urgent_escalate_hours)
    into sla_n, esc_n, sla_u, esc_u
  from public.app_settings s;

  perform set_config('approvals.advance', 'on', true);
  for r in
    select * from public.admin_requests a
     where a.status = 'pending' and a.stage is not null
       and public.workflow_specialist_role(a.request_type) is not null
       and (a.reminded_at is null or (a.escalated_at is null and a.stage in ('review', 'execute')))
     order by a.stage_since nulls first
     for update skip locked
  loop
    hrs   := extract(epoch from (now() - coalesce(r.stage_since, r.created_at, now()))) / 3600.0;
    h     := floor(hrs)::integer::text;
    sla   := case when r.priority = 'urgent' then sla_u else sla_n end;
    esc   := case when r.priority = 'urgent' then esc_u else esc_n end;
    label := public.admin_request_label(r.request_type);
    about := coalesce((select ' لـ «' || nullif(btrim(p.full_name), '') || '»' from public.profiles p where p.id = r.member_id), '');

    if r.stage in ('review', 'execute') then
      where_ := case when r.stage = 'review' then 'المراجعة' else 'التنفيذ' end;
      if hrs >= sla and r.reminded_at is null then
        update public.admin_requests set reminded_at = now() where id = r.id;
        insert into public.admin_request_steps (request_id, actor_id, actor_role, action, note, subject_id)
        values (r.id, null, 'system', 'reminded', 'تذكير تلقائي بعد ' || h || ' ساعة', r.assigned_to);
        perform public.approvals_notify(
          case when r.assigned_to is not null then array[r.assigned_to]
               else array(select public.workflow_specialist_ids(r.request_type)) end,
          'تذكير: ' || label || ' متأخر', label || about || ' بانتظار ' || where_ || ' منذ ' || h || ' ساعة',
          null, r.id, r.request_type, r.stage, 'reminded');
        n_rem := n_rem + 1;
      end if;
      if hrs >= esc and r.escalated_at is null then
        update public.admin_requests set escalated_at = now(), assigned_to = null, assigned_at = null where id = r.id;
        insert into public.admin_request_steps (request_id, actor_id, actor_role, action, note, subject_id, created_at)
        values (r.id, null, 'system', 'escalated', 'تصعيد تلقائي بعد ' || h || ' ساعة', r.assigned_to,
                now() + interval '1 millisecond');
        perform public.approvals_notify(array(select public.approvals_manager_ids()),
          'تصعيد: ' || label || ' متأخر',
          label || about || ' متأخر في ' || where_ || ' منذ ' || h || ' ساعة — تقدر تتصرف بدل المختص',
          null, r.id, r.request_type, r.stage, 'escalated');
        n_esc := n_esc + 1;
      end if;
    elsif r.stage = 'approve' then
      if hrs >= sla and r.reminded_at is null then
        update public.admin_requests set reminded_at = now() where id = r.id;
        insert into public.admin_request_steps (request_id, actor_id, actor_role, action, note, subject_id)
        values (r.id, null, 'system', 'reminded', 'تذكير تلقائي بعد ' || h || ' ساعة', r.assigned_to);
        perform public.approvals_notify(
          case when r.assigned_to is not null then array[r.assigned_to]
               else array(select public.approvals_manager_ids()) end,
          'تذكير: ' || label || ' متأخر', label || about || ' بانتظار اعتمادك منذ ' || h || ' ساعة',
          null, r.id, r.request_type, r.stage, 'reminded');
        n_rem := n_rem + 1;
      end if;
    elsif r.stage = 'info' then
      if hrs >= 48 and r.reminded_at is null then
        update public.admin_requests set reminded_at = now() where id = r.id;
        insert into public.admin_request_steps (request_id, actor_id, actor_role, action, note)
        values (r.id, null, 'system', 'reminded', 'تذكير تلقائي لصاحب الطلب بعد ' || h || ' ساعة');
        perform public.approvals_notify(array[r.requester_id], 'تذكير: الإدارة تنتظر ردّك',
          'بخصوص ' || label || ': الإدارة تنتظر المعلومات المطلوبة منذ ' || h || ' ساعة',
          null, r.id, r.request_type, r.stage, 'reminded');
        n_rem := n_rem + 1;
      end if;
    end if;
  end loop;
  perform set_config('approvals.advance', '', true);

  return jsonb_build_object('reminded', n_rem, 'escalated', n_esc);
end;
$function$;

create or replace function public.approvals_report(p_from timestamptz default null, p_to timestamptz default null)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  f       timestamptz := coalesce(p_from, now() - interval '30 days');
  t       timestamptz := coalesce(p_to, now());
  sla_n   integer;
  sla_u   integer;
  totals  jsonb;
  stages  jsonb;
  types   jsonb;
  staff   jsonb;
begin
  if coalesce(public.current_user_role(), '') not in ('owner', 'admin', 'monitor') then
    raise exception 'تقرير الموافقات للمالك والمدير والمراقب' using errcode = '42501', hint = 'not_allowed';
  end if;
  if f > t then
    raise exception 'بداية الفترة بعد نهايتها' using errcode = '22023', hint = 'bad_range';
  end if;
  select min(s.approvals_sla_hours), min(s.approvals_urgent_sla_hours) into sla_n, sla_u from public.app_settings s;

  with req as (
    select r.*, exists (select 1 from public.admin_request_steps s
                        where s.request_id = r.id and s.action = 'escalated') as was_escalated
    from public.admin_requests r
    where r.created_at >= f and r.created_at < t and public.workflow_specialist_role(r.request_type) is not null
  )
  select jsonb_build_object(
           'submitted',  count(*),
           'executed',   count(*) filter (where req.status = 'approved'),
           'rejected',   count(*) filter (where req.status = 'rejected'),
           'pending',    count(*) filter (where req.status = 'pending'),
           'urgent',     count(*) filter (where req.priority = 'urgent'),
           'escalated',  count(*) filter (where req.was_escalated),
           'fast_track', count(*) filter (where req.fast_track),
           'overdue_now', (select count(*) from public.admin_requests o
                           where o.status = 'pending' and o.stage is not null
                             and public.workflow_specialist_role(o.request_type) is not null
                             and now() - coalesce(o.stage_since, o.created_at)
                                 >= make_interval(hours => case when o.stage = 'info' then 48
                                                                when o.priority = 'urgent' then sla_u
                                                                else sla_n end)))
    into totals
  from req;

  with seg as (
    select s.created_at as started,
           lead(s.created_at) over (partition by s.request_id order by s.created_at, s.id) as ended,
           case s.action when 'submitted' then 'review' when 'provide_info' then 'review' when 'return' then 'review'
                         when 'fast_track' then 'approve' when 'recommend_approve' then 'approve'
                         when 'recommend_reject' then 'approve' when 'request_info' then 'info'
                         when 'approve' then 'execute' end as stage
    from public.admin_request_steps s
    where s.action in ('submitted', 'fast_track', 'request_info', 'provide_info', 'recommend_approve',
                       'recommend_reject', 'approve', 'return', 'executed', 'rejected')
  ), done as (
    select seg.stage, extract(epoch from (seg.ended - seg.started)) / 3600.0 as h
    from seg
    where seg.stage is not null and seg.ended is not null and seg.started >= f and seg.started < t
      and seg.ended - seg.started >= interval '1 second'
  )
  select jsonb_build_object(
           'review_hours',  round((avg(done.h) filter (where done.stage = 'review'))::numeric, 1),
           'approve_hours', round((avg(done.h) filter (where done.stage = 'approve'))::numeric, 1),
           'execute_hours', round((avg(done.h) filter (where done.stage = 'execute'))::numeric, 1),
           'info_hours',    round((avg(done.h) filter (where done.stage = 'info'))::numeric, 1))
    into stages
  from done;

  select coalesce(jsonb_agg(jsonb_build_object('type', x.request_type, 'label', public.admin_request_label(x.request_type),
                                               'count', x.n, 'executed', x.e, 'rejected', x.j)
                            order by x.n desc, x.request_type), '[]'::jsonb)
    into types
  from (select r.request_type, count(*) as n,
               count(*) filter (where r.status = 'approved') as e,
               count(*) filter (where r.status = 'rejected') as j
        from public.admin_requests r
        where r.created_at >= f and r.created_at < t and public.workflow_specialist_role(r.request_type) is not null
        group by r.request_type) x;

  with chg as (
    select s.actor_id, s.action, s.created_at,
           lag(s.created_at) over (partition by s.request_id order by s.created_at, s.id) as prev_at
    from public.admin_request_steps s
    where s.action in ('submitted', 'fast_track', 'request_info', 'provide_info', 'recommend_approve',
                       'recommend_reject', 'approve', 'return', 'executed', 'rejected')
  ), acts as (
    select s.actor_id, count(*) as n
    from public.admin_request_steps s
    where s.actor_id is not null and s.created_at >= f and s.created_at < t
      and s.action in ('recommend_approve', 'recommend_reject', 'request_info', 'approve', 'return',
                       'executed', 'rejected', 'claim', 'release', 'priority')
    group by s.actor_id
  ), resp as (
    select c.actor_id, avg(extract(epoch from (c.created_at - c.prev_at)) / 3600.0) as h
    from chg c
    where c.actor_id is not null and c.created_at >= f and c.created_at < t and c.prev_at is not null
      and c.action in ('recommend_approve', 'recommend_reject', 'request_info', 'approve', 'return', 'executed', 'rejected')
      and c.created_at - c.prev_at >= interval '1 second'
    group by c.actor_id
  ), esc as (
    select s.subject_id as actor_id, count(*) as n
    from public.admin_request_steps s
    where s.action = 'escalated' and s.subject_id is not null and s.created_at >= f and s.created_at < t
    group by s.subject_id
  ), ids as (
    select acts.actor_id from acts union select esc.actor_id from esc
  )
  select coalesce(jsonb_agg(jsonb_build_object(
             'member_id', i.actor_id,
             'name', coalesce(nullif(btrim(p.full_name), ''), p.first_name),
             'role', p.role,
             'actions', coalesce(a.n, 0),
             'avg_response_hours', round(rs.h::numeric, 1),
             'escalations', coalesce(e.n, 0))
           order by coalesce(a.n, 0) desc, coalesce(e.n, 0) desc, coalesce(p.full_name, '')), '[]'::jsonb)
    into staff
  from ids i
  left join public.profiles p on p.id = i.actor_id
  left join acts a on a.actor_id = i.actor_id
  left join resp rs on rs.actor_id = i.actor_id
  left join esc e on e.actor_id = i.actor_id;

  return jsonb_build_object(
    'period', jsonb_build_object('from', f, 'to', t),
    'totals', totals,
    'stages', stages,
    'types', types,
    'staff', staff);
end;
$function$;

-- ═══ ٣) sms_login_attempts (20261020170000) وlog_login_attempt (20261020190000) حرفياً ═══
create or replace function public.sms_login_attempts(p_days integer default 7) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_role   text := public.current_user_role();
  v_full   boolean;
  v_keep   int := coalesce((select a.login_attempts_retention_days from public.app_settings a
                             order by a.updated_at desc limit 1), 30);
  v_days   int := least(greatest(coalesce(p_days, 7), 1), v_keep);
  v_today  date := (now() at time zone 'Asia/Kuwait')::date;
  v_from   timestamptz;
  v_midnight timestamptz;
  v_items  jsonb;
  v_totals jsonb;
begin
  if coalesce(v_role, '') not in ('owner', 'admin') then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;
  v_full := v_role = 'owner';
  v_midnight := v_today::timestamp at time zone 'Asia/Kuwait';
  v_from := (v_today - (v_days - 1))::timestamp at time zone 'Asia/Kuwait';

  with g as (
    select a.phone,
           count(*)                                              as attempts,
           count(*) filter (where a.created_at >= v_midnight)    as today,
           count(*) filter (where a.outcome = 'sent')            as sent,
           count(*) filter (where a.outcome = 'blocked')         as blocked,
           count(*) filter (where a.outcome = 'failed')          as failed,
           count(*) filter (where a.outcome = 'unknown')         as unknown,
           count(*) filter (where a.outcome = 'test')            as test,
           min(a.created_at)                                     as first_at,
           max(a.created_at)                                     as last_at,
           (array_agg(a.outcome order by a.created_at desc, a.id desc))[1] as last_outcome,
           (array_agg(a.profile_id order by a.created_at desc, a.id desc)
              filter (where a.profile_id is not null))[1]       as stored_profile
      from public.login_attempts a
     where a.created_at >= v_from
     group by a.phone
  ), h as (
    select x.phone, max(x.n) as max_in_hour
      from (select a.phone, count(*) as n
              from public.login_attempts a
             where a.created_at >= v_from
             group by a.phone, date_trunc('hour', a.created_at)) x
     group by x.phone
  ), r as (
    select g.*, h.max_in_hour, p.id as profile_id, p.full_name, p.first_name, p.status as member_status,
           (select max(u.last_sign_in_at) from auth.users u where u.phone = g.phone) as last_sign_in_at
      from g
      join h on h.phone = g.phone
      left join lateral (
        select pp.id, pp.full_name, pp.first_name, pp.status
          from public.profiles pp
         where pp.id = coalesce(public.login_attempt_profile_id(g.phone), g.stored_profile)
      ) p on true
  )
  select
    jsonb_build_object(
      'phones', count(*),
      'attempts', coalesce(sum(r.attempts), 0),
      'unknown_numbers', count(*) filter (where r.profile_id is null),
      'suspicious', count(*) filter (where r.max_in_hour >= 5)),
    coalesce((select jsonb_agg(j order by t.last_at desc, t.phone)
                from (select r2.last_at, r2.phone, jsonb_build_object(
                        'phone', '+965 ' || case when v_full then substr(r2.phone, 4)
                                                 else substr(r2.phone, 4, 4) || '••' || right(r2.phone, 2) end,
                        'phone_e164', case when v_full then '+' || r2.phone end,
                        'profile_id', r2.profile_id,
                        'name', coalesce(nullif(btrim(r2.full_name), ''), nullif(btrim(r2.first_name), '')),
                        'is_member', r2.profile_id is not null,
                        'member_status', r2.member_status,
                        'attempts_today', r2.today,
                        'attempts_in_window', r2.attempts,
                        'sent', r2.sent,
                        'blocked', r2.blocked,
                        'failed', r2.failed,
                        'unknown', r2.unknown,
                        'test', r2.test,
                        'first_at', r2.first_at,
                        'last_at', r2.last_at,
                        'last_outcome', r2.last_outcome,
                        'logged_in', coalesce(r2.last_sign_in_at >= r2.first_at, false),
                        'last_sign_in_at', r2.last_sign_in_at,
                        'max_in_hour', r2.max_in_hour,
                        'suspicious', r2.max_in_hour >= 5) j
                        from r r2
                       order by r2.last_at desc, r2.phone
                       limit 200) t), '[]'::jsonb)
    into v_totals, v_items
    from r;

  return jsonb_build_object(
    'days', v_days,
    'masked', not v_full,
    'retention_days', v_keep,
    'generated_at', now(),
    'totals', v_totals,
    'items', v_items);
end;
$$;

create or replace function public.log_login_attempt(p_phone text, p_outcome text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_keep    int;
  v_id      bigint;
  v_profile uuid;
  v_n       int;
  v_name    text;
begin
  if p_phone is null or p_phone !~ '^965[4569][0-9]{7}$'
     or p_outcome is null or p_outcome not in ('sent', 'failed', 'unknown', 'blocked', 'test') then
    raise exception 'Invalid login attempt' using errcode = '22023';
  end if;
  v_profile := public.login_attempt_profile_id(p_phone);
  insert into public.login_attempts (phone, profile_id, outcome)
  values (p_phone, v_profile, p_outcome)
  returning id into v_id;
  select a.login_attempts_retention_days into v_keep
    from public.app_settings a order by a.updated_at desc limit 1;
  delete from public.login_attempts
   where id in (select a.id from public.login_attempts a
                 where a.created_at < now() - make_interval(days => coalesce(v_keep, 30))
                 order by a.created_at limit 200);

  -- تنبيه «محاولات دخول مريبة» — بأفضل جهد: أي خطأ هنا يتراجع وحده ولا يصل للدالة الطرفية
  begin
    select count(*) into v_n from public.login_attempts a
     where a.phone = p_phone and a.created_at > now() - interval '60 minutes';
    -- القفل غير منتظِر: محاولة متزامنة لنفس الرقم تتركه لصاحبة القفل
    if v_n >= 5 and pg_catalog.pg_try_advisory_xact_lock(20261020, pg_catalog.hashtext(p_phone)) then
      -- عبارة منفصلة بعد القفل (لقطة جديدة) ترى تنبيهاً التزم للتو
      if not exists (select 1 from public.login_attempts a
                      where a.phone = p_phone and a.alerted
                        and a.created_at > now() - interval '12 hours') then
        update public.login_attempts set alerted = true where id = v_id;
        select coalesce(nullif(btrim(p.full_name), ''), nullif(btrim(p.first_name), '')) into v_name
          from public.profiles p where p.id = v_profile;
        insert into public.notifications (target_member_id, title, body, kind, created_by, is_read)
        select p.id, 'محاولات دخول مريبة',
               coalesce(v_name, 'رقم غير مسجّل') || ' طلب رمز الدخول ' || v_n || ' مرات خلال ساعة — +965 '
               || case when p.role = 'owner' then substr(p_phone, 4)
                       else substr(p_phone, 4, 4) || '••' || right(p_phone, 2) end,
               'sms_suspicious', null, false
          from public.profiles p
         where p.role in ('owner', 'admin') and p.status = 'active';
      end if;
    end if;
  exception when others then
    raise warning 'log_login_attempt: suspicious alert skipped (%)', sqlstate;
  end;
end;
$$;

revoke all on function public.log_login_attempt(text, text) from public, anon, authenticated;
grant execute on function public.log_login_attempt(text, text) to service_role;

-- ═══ ٤) reserve_kwtsms_send كما في 20261020170000 حرفياً («create or replace» بدل «create» لأنها موجودة) ═══
create or replace function public.reserve_kwtsms_send(p_event text, p_phone text, p_test boolean, p_format integer default 1)
returns text language plpgsql security definer set search_path = '' as $function$
declare
  v_now timestamptz := clock_timestamp(); v_existing text;
  v_wait int; v_per_number int; v_all_hour int; v_sender text;
  v_at timestamptz; v_left numeric := 0;
begin
  if p_event !~ '^[a-f0-9]{64}$' or p_phone !~ '^[a-f0-9]{64}$' or p_test is null then
    raise exception 'Invalid reservation';
  end if;
  -- Serializes short reservations across Edge instances; never held during a provider call.
  perform pg_advisory_xact_lock(19200000, 1);
  delete from public.kwtsms_deliveries where created_at < v_now - interval '2 days';
  select outcome into v_existing from public.kwtsms_deliveries where event_hash = p_event;
  if found then return case when v_existing = 'accepted' then 'accepted' else 'blocked' end; end if;
  -- الحدود من app_settings (المالك)؛ بلا سطر/قيمة ← الثوابت السابقة
  select a.sms_wait_seconds, a.sms_per_number_hour, a.sms_all_hour, a.sms_sender
    into v_wait, v_per_number, v_all_hour, v_sender
    from public.app_settings a order by a.updated_at desc limit 1;
  v_wait := coalesce(v_wait, 60);  v_per_number := coalesce(v_per_number, 5);  v_all_hour := coalesce(v_all_hour, 100);
  -- مهلة الرقم: الحجز يُمنع (الانتظار - ١٠ ث)، والباقي يُحسب على الانتظار المعلن
  select max(d.created_at) into v_at from public.kwtsms_deliveries d
   where d.phone_hash = p_phone and d.created_at > v_now - make_interval(secs => v_wait - 10);
  if v_at is not null then
    v_left := greatest(v_left, extract(epoch from (v_at + make_interval(secs => v_wait) - v_now)));
  end if;
  -- حد الرقم بالساعة: يفرج لما يطلع من نافذة الساعة الإرسال رقم (الحد) من الأحدث
  select d.created_at into v_at from public.kwtsms_deliveries d
   where d.phone_hash = p_phone and d.created_at > v_now - interval '1 hour'
   order by d.created_at desc offset v_per_number - 1 limit 1;
  if v_at is not null then
    v_left := greatest(v_left, extract(epoch from (v_at + interval '1 hour' - v_now)));
  end if;
  -- الكل: ٥ بالثانية
  select d.created_at into v_at from public.kwtsms_deliveries d
   where d.created_at > v_now - interval '1 second'
   order by d.created_at desc offset 4 limit 1;
  if v_at is not null then
    v_left := greatest(v_left, extract(epoch from (v_at + interval '1 second' - v_now)));
  end if;
  -- الكل بالساعة
  select d.created_at into v_at from public.kwtsms_deliveries d
   where d.created_at > v_now - interval '1 hour'
   order by d.created_at desc offset v_all_hour - 1 limit 1;
  if v_at is not null then
    v_left := greatest(v_left, extract(epoch from (v_at + interval '1 hour' - v_now)));
  end if;
  if v_left > 0 then
    return case when coalesce(p_format, 1) >= 2 then 'blocked:' || greatest(ceil(v_left), 1)::int else 'blocked' end;
  end if;
  insert into public.kwtsms_deliveries(event_hash,phone_hash,test_mode,created_at)
    values (p_event,p_phone,p_test,v_now);
  -- الرد المفصّل: المرسل المحفوظ إن وُجد (الدالة الطرفية تتحقق منه مرة ثانية)؛ الرد القديم «send» حرفياً
  if coalesce(p_format, 1) >= 2 and v_sender ~ '^[A-Za-z0-9 -]{1,11}$' then
    return 'send:' || v_sender;
  end if;
  return 'send';
end;
$function$;
revoke all on function public.reserve_kwtsms_send(text, text, boolean, integer) from public, anon, authenticated;
grant execute on function public.reserve_kwtsms_send(text, text, boolean, integer) to service_role;
