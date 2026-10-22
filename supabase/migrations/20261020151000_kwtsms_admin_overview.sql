-- رسائل الدخول · KWT SMS (صفحة الإدارة الجديدة) — الجزء ٢: قراءة الإدارة + دوال الدالة الطرفية kwtsms-admin.
-- مُعدّ ٢٠٢٦-١٠-٢٠ ولم يُطبَّق — ينتظر «نعم» المالك. يحتاج 20261020150000_kwtsms_daily_stats قبله.
--  ١) sms_admin_overview() — للمالك والمدير فقط (غيرهما 42501): آخر رصيد معروف وحالته (جيد/منخفض/عاجل حسب
--     العتبات)، أرقام اليوم/٧/٣٠ يوماً ونسبة القبول، معدّل النقاط اليومي (٧ أيام)، آخر ٣٠ يوماً يوماً بيوم، عدّاد
--     الساعة الحالية مقابل الحد (١٠٠)، الحدود، إعدادات التنبيه، وآخر ٥٠ إرسالاً. لا رقم هاتف ولا بصمة كاملة:
--     من بصمة الرقم آخر ٤ خانات فقط (للتمييز بين الأرقام)، وبصمة الحدث لا تخرج أبداً.
--  ٢) للدالة الطرفية kwtsms-admin فقط (service_role، لا تنفيذ للتطبيقات):
--     reserve_kwtsms_admin_test — «اختبار إرسال لرقمي»: مرة كل ١٠ دقائق، ويحترم مهلة الرقم (٥٠ ث) وحدود الكل
--       (٥ بالثانية، ١٠٠ بالساعة) حتى ما يزاحم رموز الدخول؛ يُسجَّل admin_test فيُعدّ «تجريبي» لا رمز دخول.
--     record_kwtsms_delivery_status — يحفظ نتيجة فحص «status» من KWT على الإرسال برقم الرسالة.
--     record_kwtsms_balance — يحفظ «تحديث الرصيد الآن» في السجل اليومي (فيظهر بعد الشحن بدون انتظار إرسال).
-- التراجع: supabase/rollback/20261020151000_kwtsms_admin_overview_rollback.sql
-- تجربة محلية: cd supabase/tests/family_links && node kwtsms_admin_stats.test.mjs

-- ١) قراءة الإدارة
create function public.sms_admin_overview() returns jsonb
language plpgsql security definer set search_path = '' stable as $$
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

  -- آخر رصيد معروف (إرسال مقبول غير تجريبي، أو «تحديث الرصيد الآن»)
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

  -- نفس عدّاد reserve_kwtsms_send (كل الحجوزات في آخر ساعة)
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
$$;
revoke all on function public.sms_admin_overview() from public, anon;
grant execute on function public.sms_admin_overview() to authenticated;

-- ٢-أ) «اختبار إرسال لرقمي» — الحجز (المالك يُتحقق منه في الدالة الطرفية)
create function public.reserve_kwtsms_admin_test(p_event text, p_phone text, p_test boolean)
returns text language plpgsql security definer set search_path = '' as $$
declare v_now timestamptz := clock_timestamp();
begin
  if p_event is null or p_event !~ '^[a-f0-9]{64}$' or p_phone is null or p_phone !~ '^[a-f0-9]{64}$'
     or p_test is null then
    raise exception 'Invalid reservation';
  end if;
  -- نفس قفل reserve_kwtsms_send: الحجوزات تتسلسل بين نسخ الدوال
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
$$;

-- ٢-ب) نتيجة فحص «status» (KWT: حالة الطابور فقط — أرقام الكويت ما لها تقرير وصول من المزوّد)
create function public.record_kwtsms_delivery_status(p_msgid text, p_status text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if p_msgid is null or p_msgid !~ '^[A-Za-z0-9-]{1,64}$'
     or p_status is null or p_status !~ '^[A-Za-z0-9 _.:-]{1,40}$' then
    raise exception 'Invalid delivery status';
  end if;
  update public.kwtsms_deliveries
     set delivery_status = p_status, delivery_checked_at = clock_timestamp()
   where provider_msgid = p_msgid;
  return found;
end;
$$;

-- ٢-ج) «تحديث الرصيد الآن» — يدخل السجل اليومي كآخر رصيد معروف
create function public.record_kwtsms_balance(p_balance numeric)
returns void language plpgsql security definer set search_path = '' as $$
declare v_now timestamptz := clock_timestamp();
begin
  if p_balance is null or p_balance < 0 or p_balance > 100000000 then
    raise exception 'Invalid balance';
  end if;
  insert into public.kwtsms_daily_stats as s (day, first_balance, last_balance, balance_at)
  values ((v_now at time zone 'Asia/Kuwait')::date, p_balance, p_balance, v_now)
  on conflict (day) do update set
    first_balance = coalesce(s.first_balance, excluded.first_balance),
    last_balance  = case when excluded.balance_at >= coalesce(s.balance_at, '-infinity')
                         then excluded.last_balance else s.last_balance end,
    balance_at    = greatest(s.balance_at, excluded.balance_at),
    updated_at    = now();
end;
$$;

revoke all on function public.reserve_kwtsms_admin_test(text, text, boolean) from public, anon, authenticated;
revoke all on function public.record_kwtsms_delivery_status(text, text) from public, anon, authenticated;
revoke all on function public.record_kwtsms_balance(numeric) from public, anon, authenticated;
grant execute on function public.reserve_kwtsms_admin_test(text, text, boolean) to service_role;
grant execute on function public.record_kwtsms_delivery_status(text, text) to service_role;
grant execute on function public.record_kwtsms_balance(numeric) to service_role;
