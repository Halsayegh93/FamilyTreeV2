-- تراجع 20261020170000_kwtsms_editable_limits: يعيد الدوال الخمس كما هي على السيرفر الحي حرفياً (pg_get_functiondef،
-- قراءة فقط ٢٠٢٦-١٠-٢٠ — md5 في tests/family_links/kwtsms_editable_limits.test.mjs) ويحذف الحارس ودالة المرسل والأعمدة
-- الخمسة. القيم التي عدّلها المالك تضيع (ترجع الثوابت: ٥٠ ث، ٥/ساعة للرقم، ١٠٠/ساعة للكل، ٣٠ يوماً، المرسل الافتراضي).
-- الترتيب: أرجع الدالة الطرفية send-sms-kwtsms (و kwtsms-admin) للنسخة السابقة أولاً، ثم هذا الملف.
-- (لو بقيت الجديدة: تطلب p_format فيرفضها PostgREST بـ 404 فتعيد بالعقد القديم تلقائياً — تعمل بلا انقطاع.)

drop trigger if exists trg_app_settings_sms_sender_guard on public.app_settings;
drop function if exists public.app_settings_sms_sender_guard();
drop function if exists public.set_kwtsms_sender(text, uuid);

drop function public.reserve_kwtsms_send(text, text, boolean, integer);
CREATE OR REPLACE FUNCTION public.reserve_kwtsms_send(p_event text, p_phone text, p_test boolean)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_now timestamptz := clock_timestamp(); v_existing text;
begin
  if p_event !~ '^[a-f0-9]{64}$' or p_phone !~ '^[a-f0-9]{64}$' or p_test is null then
    raise exception 'Invalid reservation';
  end if;
  -- Serializes short reservations across Edge instances; never held during a provider call.
  perform pg_advisory_xact_lock(19200000, 1);
  delete from public.kwtsms_deliveries where created_at < v_now - interval '2 days';
  select outcome into v_existing from public.kwtsms_deliveries where event_hash = p_event;
  if found then return case when v_existing = 'accepted' then 'accepted' else 'blocked' end; end if;
  if exists (select 1 from public.kwtsms_deliveries where phone_hash = p_phone
      and created_at > v_now - interval '50 seconds')
    or (select count(*) from public.kwtsms_deliveries where phone_hash = p_phone
      and created_at > v_now - interval '1 hour') >= 5
    or (select count(*) from public.kwtsms_deliveries
      where created_at > v_now - interval '1 second') >= 5
    or (select count(*) from public.kwtsms_deliveries
      where created_at > v_now - interval '1 hour') >= 100 then
    return 'blocked';
  end if;
  insert into public.kwtsms_deliveries(event_hash,phone_hash,test_mode,created_at)
    values (p_event,p_phone,p_test,v_now);
  return 'send';
end;
$function$
;
revoke all on function public.reserve_kwtsms_send(text, text, boolean) from public, anon, authenticated;
grant execute on function public.reserve_kwtsms_send(text, text, boolean) to service_role;

CREATE OR REPLACE FUNCTION public.reserve_kwtsms_admin_test(p_event text, p_phone text, p_test boolean)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_now timestamptz := clock_timestamp();
begin
  if p_event is null or p_event !~ '^[a-f0-9]{64}$' or p_phone is null or p_phone !~ '^[a-f0-9]{64}$'
     or p_test is null then
    raise exception 'Invalid reservation';
  end if;
  perform pg_advisory_xact_lock(19200000, 1);
  if exists (select 1 from public.kwtsms_deliveries where event_hash = p_event) then
    return 'blocked';
  end if;
  if exists (select 1 from public.kwtsms_deliveries
              where admin_test and created_at > v_now - interval '10 minutes') then
    return 'wait';
  end if;
  if exists (select 1 from public.kwtsms_deliveries where phone_hash = p_phone
      and created_at > v_now - interval '50 seconds')
    or (select count(*) from public.kwtsms_deliveries
      where created_at > v_now - interval '1 second') >= 5
    or (select count(*) from public.kwtsms_deliveries
      where created_at > v_now - interval '1 hour') >= 100 then
    return 'blocked';
  end if;
  insert into public.kwtsms_deliveries(event_hash, phone_hash, test_mode, admin_test, created_at)
    values (p_event, p_phone, p_test, true, v_now);
  return 'send';
end;
$function$
;

CREATE OR REPLACE FUNCTION public.log_login_attempt(p_phone text, p_outcome text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if p_phone is null or p_phone !~ '^965[4569][0-9]{7}$'
     or p_outcome is null or p_outcome not in ('sent', 'failed', 'unknown', 'blocked', 'test') then
    raise exception 'Invalid login attempt' using errcode = '22023';
  end if;
  insert into public.login_attempts (phone, profile_id, outcome)
  values (p_phone, public.login_attempt_profile_id(p_phone), p_outcome);
  delete from public.login_attempts
   where id in (select a.id from public.login_attempts a
                 where a.created_at < now() - interval '30 days'
                 order by a.created_at limit 200);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.sms_login_attempts(p_days integer DEFAULT 7)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_role   text := public.current_user_role();
  v_full   boolean;
  v_days   int := least(greatest(coalesce(p_days, 7), 1), 30);
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
    'retention_days', 30,
    'generated_at', now(),
    'totals', v_totals,
    'items', v_items);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.sms_admin_overview()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_today   date := (now() at time zone 'Asia/Kuwait')::date;
  v_low     int;
  v_crit    int;
  v_low_h   int;
  v_crit_h  int;
  v_bal     numeric;
  v_bal_at  timestamptz;
  v_pts7    numeric;
  v_totals  jsonb;
  v_days    jsonb;
  v_hour    int;
  v_mode    boolean;
  v_recent  jsonb;
begin
  if coalesce(public.current_user_role(), '') not in ('owner', 'admin') then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;

  select a.sms_low_threshold, a.sms_urgent_threshold, a.sms_low_repeat_hours, a.sms_urgent_repeat_hours
    into v_low, v_crit, v_low_h, v_crit_h
    from public.app_settings a order by a.updated_at desc limit 1;
  v_low := coalesce(v_low, 50);  v_crit := coalesce(v_crit, 10);
  v_low_h := coalesce(v_low_h, 24);  v_crit_h := coalesce(v_crit_h, 12);

  select s.last_balance, s.balance_at into v_bal, v_bal_at
    from public.kwtsms_daily_stats s
   where s.last_balance is not null
   order by s.balance_at desc nulls last limit 1;

  select jsonb_object_agg(w.k, t.j) into v_totals
    from (values ('today', 1), ('days_7', 7), ('days_30', 30)) w(k, n)
    cross join lateral (
      select jsonb_build_object(
        'sends', coalesce(sum(s.sends), 0),
        'accepted', coalesce(sum(s.accepted), 0),
        'failed', coalesce(sum(s.failed), 0),
        'unknown', coalesce(sum(s.unknown), 0),
        'test_sends', coalesce(sum(s.test_sends), 0),
        'points', coalesce(sum(s.points), 0),
        'acceptance_pct', case when sum(s.sends) > 0
                               then round(100.0 * sum(s.accepted) / sum(s.sends), 1) end) j
        from public.kwtsms_daily_stats s
       where s.day > v_today - w.n and s.day <= v_today) t;

  select coalesce(sum(s.points), 0) into v_pts7
    from public.kwtsms_daily_stats s where s.day > v_today - 7 and s.day <= v_today;

  select coalesce(jsonb_agg(jsonb_build_object(
           'day', s.day, 'sends', s.sends, 'accepted', s.accepted, 'failed', s.failed,
           'unknown', s.unknown, 'test_sends', s.test_sends, 'points', s.points,
           'balance', s.last_balance) order by s.day), '[]'::jsonb)
    into v_days
    from public.kwtsms_daily_stats s where s.day > v_today - 30 and s.day <= v_today;

  select count(*) into v_hour from public.kwtsms_deliveries d
   where d.created_at > now() - interval '1 hour';

  select d.test_mode into v_mode from public.kwtsms_deliveries d
   where not d.admin_test order by d.created_at desc limit 1;

  select coalesce(jsonb_agg(x.j order by x.created_at desc), '[]'::jsonb) into v_recent
    from (select d.created_at, jsonb_build_object(
            'at', d.created_at,
            'outcome', d.outcome,
            'error_code', d.error_code,
            'delivery_status', d.delivery_status,
            'delivery_checked_at', d.delivery_checked_at,
            'points', d.points_charged,
            'balance_after', d.balance_after,
            'msgid', d.provider_msgid,
            'test', d.test_mode,
            'admin_test', d.admin_test,
            'phone_tail', right(d.phone_hash, 4)) j
            from public.kwtsms_deliveries d
           order by d.created_at desc
           limit 50) x;

  return jsonb_build_object(
    'balance', v_bal,
    'balance_at', v_bal_at,
    'balance_state', case when v_bal is null then null
                          when v_bal < v_crit then 'urgent'
                          when v_bal < v_low then 'low'
                          else 'ok' end,
    'avg_daily_points_7d', round(v_pts7 / 7.0, 2),
    'totals', v_totals,
    'days', v_days,
    'hour', jsonb_build_object('count', v_hour, 'cap', 100),
    'limits', jsonb_build_object('phone_cooldown_seconds', 50, 'phone_per_hour', 5,
                                 'all_per_second', 5, 'all_per_hour', 100, 'admin_test_minutes', 10),
    'alerts', jsonb_build_object('low_threshold', v_low, 'urgent_threshold', v_crit,
                                 'low_repeat_hours', v_low_h, 'urgent_repeat_hours', v_crit_h,
                                 'recipients', 'owner_admins'),
    'last_test_mode', v_mode,
    'retention_days', 2,
    'recent', v_recent);
end;
$function$
;

alter table public.app_settings
  drop column sms_wait_seconds,
  drop column sms_per_number_hour,
  drop column sms_all_hour,
  drop column login_attempts_retention_days,
  drop column sms_sender;
