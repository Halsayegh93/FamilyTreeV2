-- رسائل الدخول · KWT SMS — حدود الإرسال واسم المرسل يعدّلها المالك (طلب المالك ٢٠٢٦-١٠-٢٠ «نقدر نغير البيانات؟ مثل
-- وقت الانتظار» — اختار الأربعة، ثم «وخانة اسم المرسل؟»). مُعدّ ولم يُطبَّق — ينتظر «نعم» المالك.
--  ١) app_settings (سطر واحد بأعمدة) — الافتراضي = السلوك الحالي حرفياً، فلا يتغير شيء حتى يعدّلها المالك:
--     sms_wait_seconds ٦٠ (٦٠..٦٠٠) — الانتظار بين رمزين لنفس الرقم كما يراه العضو. داخلياً مهلة الحجز = الانتظار - ١٠ ث
--       (٥٠ ث اليوم) حتى ما تتصادم مع مهلة Supabase نفسها (٦٠ ث، تُعدَّل من لوحة Supabase فقط — لذلك لا أقل من ٦٠).
--     sms_per_number_hour ٥ (١..٢٠) — رموز لنفس الرقم بالساعة.   sms_all_hour ١٠٠ (٢٠..١٠٠٠) — رموز للكل بالساعة.
--     login_attempts_retention_days ٣٠ (٧..٩٠) — حفظ «محاولات الدخول» (وأقصى فترة لعرضها).
--     sms_sender — اسم المرسل (فارغ = المرسل الافتراضي للدالة الطرفية «KWT-SMS»). لا يكتبه التطبيق مباشرة أبداً:
--       مرسل غير معتمد في حساب KWT يوقف كل رسائل الدخول، فالتغيير عبر kwtsms-admin «set_sender» فقط (المالك، ويتحقق
--       من قائمة KWT المعتمدة) ← set_kwtsms_sender (service_role). الحارس trg_app_settings_sms_sender_guard يرفض أي
--       تغيير له من جلسة التطبيقات (authenticated/anon) حتى لو كانت للمالك؛ صيانة SQL بلا مستخدم مسموحة.
--     التعديل للمالك فقط (سياسة «Owner can update app_settings» كما هي — المدير يقرأ ولا يعدّل).
--  ٢) reserve_kwtsms_send: نفس الحدود من الإعدادات + معامل اختياري p_format (افتراضي ١ = الردود القديمة حرفياً
--     «send»/«blocked»/«accepted»، فالدالة الطرفية المنشورة v20 تبقى تعمل). p_format = ٢ (الدالة الطرفية الجديدة):
--     «send:<المرسل>» لما يكون محفوظاً، و«blocked:<ثوانٍ>» = متى يقدر يطلب (على الانتظار المعلن؛ أكبر حد من الأربعة).
--     الدالة القديمة بثلاثة معاملات تُحذف وتُنشأ الجديدة في نفس المعاملة (PostgREST يستدعي بالأسماء، فالثلاثة تكفي).
--  ٣) reserve_kwtsms_admin_test: مهلة الرقم والحد بالساعة من الإعدادات؛ الردود كما هي.
--  ٤) log_login_attempt / sms_login_attempts: مدة الحفظ من الإعدادات (وسقف p_days = المدة؛ retention_days = المدة).
--  ٥) sms_admin_overview: «limits» و«hour.cap» من الإعدادات (+ wait_seconds)، «retention» (الإرسالات ٢ يوم + المحاولات)،
--     و«sender» {current, default, source}. باقي الرد كما هو.
-- التراجع: supabase/rollback/20261020170000_kwtsms_editable_limits_rollback.sql (يعيد تعريفات الحي حرفياً + يحذف الأعمدة)
-- تجربة محلية: cd supabase/tests/family_links && node kwtsms_editable_limits.test.mjs

-- ١) الأعمدة
alter table public.app_settings
  add column sms_wait_seconds integer not null default 60
    check (sms_wait_seconds between 60 and 600),
  add column sms_per_number_hour integer not null default 5
    check (sms_per_number_hour between 1 and 20),
  add column sms_all_hour integer not null default 100
    check (sms_all_hour between 20 and 1000),
  add column login_attempts_retention_days integer not null default 30
    check (login_attempts_retention_days between 7 and 90),
  add column sms_sender text
    check (sms_sender ~ '^[A-Za-z0-9 -]{1,11}$');

-- اسم المرسل: لا تغيير من جلسة التطبيقات (ولا عبر دالة SECURITY DEFINER يستدعيها مستخدم) — الخدمة أو صيانة SQL فقط
create function public.app_settings_sms_sender_guard() returns trigger
language plpgsql set search_path = '' as $$
declare
  v_jwt_role text := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
begin
  if new.sms_sender is distinct from old.sms_sender
     and (current_user in ('anon', 'authenticated') or v_jwt_role not in ('', 'service_role')) then
    raise exception 'اسم المرسل يتغيّر من صفحة «رسائل الدخول» فقط (يُتحقق من اعتماده في KWT)'
      using errcode = '42501', hint = 'sms_sender_service_only';
  end if;
  return new;
end;
$$;
revoke all on function public.app_settings_sms_sender_guard() from public, anon, authenticated;
create trigger trg_app_settings_sms_sender_guard before update on public.app_settings
  for each row execute function public.app_settings_sms_sender_guard();

-- حفظ اسم المرسل (kwtsms-admin «set_sender» فقط، بعد التحقق من قائمة KWT). null = الرجوع للافتراضي.
create function public.set_kwtsms_sender(p_sender text, p_by uuid default null) returns text
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_out text;
begin
  if p_sender is not null and p_sender !~ '^[A-Za-z0-9 -]{1,11}$' then
    raise exception 'Invalid sender' using errcode = '22023';
  end if;
  select a.id into v_id from public.app_settings a order by a.updated_at desc limit 1 for update;
  if v_id is null then
    raise exception 'app_settings missing' using errcode = 'P0002';
  end if;
  update public.app_settings a
     set sms_sender = p_sender,
         updated_at = now(),
         updated_by = coalesce((select p.id from public.profiles p where p.id = p_by), a.updated_by)
   where a.id = v_id
  returning a.sms_sender into v_out;
  return v_out;
end;
$$;
revoke all on function public.set_kwtsms_sender(text, uuid) from public, anon, authenticated;
grant execute on function public.set_kwtsms_sender(text, uuid) to service_role;

-- ٢) الحجز: نفس السلوك + الحدود من الإعدادات + الرد المفصّل عند الطلب
drop function public.reserve_kwtsms_send(text, text, boolean);
create function public.reserve_kwtsms_send(p_event text, p_phone text, p_test boolean, p_format integer default 1)
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

-- ٣) «اختبار إرسال لرقمي»: مهلة الرقم والحد بالساعة من الإعدادات (الردود كما هي: send / wait / blocked)
create or replace function public.reserve_kwtsms_admin_test(p_event text, p_phone text, p_test boolean)
returns text language plpgsql security definer set search_path = '' as $$
declare v_now timestamptz := clock_timestamp(); v_wait int; v_all_hour int;
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
  select a.sms_wait_seconds, a.sms_all_hour into v_wait, v_all_hour
    from public.app_settings a order by a.updated_at desc limit 1;
  v_wait := coalesce(v_wait, 60);  v_all_hour := coalesce(v_all_hour, 100);
  if exists (select 1 from public.kwtsms_deliveries where phone_hash = p_phone
      and created_at > v_now - make_interval(secs => v_wait - 10))
    or (select count(*) from public.kwtsms_deliveries
      where created_at > v_now - interval '1 second') >= 5
    or (select count(*) from public.kwtsms_deliveries
      where created_at > v_now - interval '1 hour') >= v_all_hour then
    return 'blocked';
  end if;
  insert into public.kwtsms_deliveries(event_hash, phone_hash, test_mode, admin_test, created_at)
    values (p_event, p_phone, p_test, true, v_now);
  return 'send';
end;
$$;

-- ٤-أ) تسجيل المحاولة: الحفظ حسب الإعدادات (الافتراضي ٣٠ يوماً)
create or replace function public.log_login_attempt(p_phone text, p_outcome text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_keep int;
begin
  if p_phone is null or p_phone !~ '^965[4569][0-9]{7}$'
     or p_outcome is null or p_outcome not in ('sent', 'failed', 'unknown', 'blocked', 'test') then
    raise exception 'Invalid login attempt' using errcode = '22023';
  end if;
  insert into public.login_attempts (phone, profile_id, outcome)
  values (p_phone, public.login_attempt_profile_id(p_phone), p_outcome);
  select a.login_attempts_retention_days into v_keep
    from public.app_settings a order by a.updated_at desc limit 1;
  delete from public.login_attempts
   where id in (select a.id from public.login_attempts a
                 where a.created_at < now() - make_interval(days => coalesce(v_keep, 30))
                 order by a.created_at limit 200);
end;
$$;

-- ٤-ب) القراءة: سقف الفترة = مدة الحفظ
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

-- ٥) قراءة الإدارة: الحدود والحفظ والمرسل من الإعدادات
create or replace function public.sms_admin_overview() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_today   date := (now() at time zone 'Asia/Kuwait')::date;
  v_low     int;
  v_crit    int;
  v_low_h   int;
  v_crit_h  int;
  v_wait    int;
  v_per_number int;
  v_all_hour int;
  v_keep    int;
  v_sender  text;
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

  select a.sms_low_threshold, a.sms_urgent_threshold, a.sms_low_repeat_hours, a.sms_urgent_repeat_hours,
         a.sms_wait_seconds, a.sms_per_number_hour, a.sms_all_hour, a.login_attempts_retention_days, a.sms_sender
    into v_low, v_crit, v_low_h, v_crit_h, v_wait, v_per_number, v_all_hour, v_keep, v_sender
    from public.app_settings a order by a.updated_at desc limit 1;
  v_low := coalesce(v_low, 50);  v_crit := coalesce(v_crit, 10);
  v_low_h := coalesce(v_low_h, 24);  v_crit_h := coalesce(v_crit_h, 12);
  v_wait := coalesce(v_wait, 60);  v_per_number := coalesce(v_per_number, 5);
  v_all_hour := coalesce(v_all_hour, 100);  v_keep := coalesce(v_keep, 30);

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
    'hour', jsonb_build_object('count', v_hour, 'cap', v_all_hour),
    'limits', jsonb_build_object('wait_seconds', v_wait, 'phone_cooldown_seconds', v_wait - 10,
                                 'phone_per_hour', v_per_number, 'all_per_second', 5,
                                 'all_per_hour', v_all_hour, 'admin_test_minutes', 10),
    'alerts', jsonb_build_object('low_threshold', v_low, 'urgent_threshold', v_crit,
                                 'low_repeat_hours', v_low_h, 'urgent_repeat_hours', v_crit_h,
                                 'recipients', 'owner_admins'),
    'sender', jsonb_build_object('current', coalesce(v_sender, 'KWT-SMS'), 'default', 'KWT-SMS',
                                 'source', case when v_sender is null then 'default' else 'settings' end),
    'last_test_mode', v_mode,
    'retention_days', 2,
    'retention', jsonb_build_object('deliveries_days', 2, 'login_attempts_days', v_keep),
    'recent', v_recent);
end;
$$;
