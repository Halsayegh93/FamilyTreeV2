-- رسائل الدخول · KWT SMS (صفحة الإدارة الجديدة) — الجزء ١: سجل يومي دائم + سبب الفشل + عتبات تنبيه قابلة للتعديل.
-- مُعدّ ٢٠٢٦-١٠-٢٠ ولم يُطبَّق — ينتظر «نعم» المالك.
--  ١) kwtsms_daily_stats: سطر لكل يوم (بتوقيت الكويت، يوم الحجز). kwtsms_deliveries تُحذف بعد يومين، فبدون هذا
--     أرقام ٧/٣٠ يوماً واتجاه الرصيد مستحيلة. بلا أرقام هواتف ولا بصمات. مقفول عن التطبيقات (القراءة عبر
--     sms_admin_overview في 20261020151000). يُعبّأ من الإرسالات الموجودة الآن (آخر يومين).
--  ٢) kwtsms_deliveries: error_code (مثل ERR028 — اليوم الفشل بلا سبب)، delivery_status + delivery_checked_at
--     (فحص «status» من KWT)، admin_test (رسالة «اختبار إرسال لرقمي» من المالك — تُعدّ «تجريبية» لا رمز دخول).
--  ٣) finish_kwtsms_send: نفس السلوك حرفياً + يحدّث السجل اليومي + معامل اختياري جديد p_error_code (افتراضي null)
--     — الدالة المنشورة send-sms-kwtsms تبقى تعمل بلا أي تعديل (تستدعيها بالأسماء الخمسة). الدالة القديمة بخمسة
--     معاملات تُحذف وتُنشأ الجديدة في نفس المعاملة حتى ما يصير عندنا نسختان (PostgREST يرفض الاستدعاء لو تشابهتا).
--  ٤) app_settings (سطر واحد بأعمدة): sms_low_threshold ٥٠، sms_urgent_threshold ١٠، sms_low_repeat_hours ٢٤،
--     sms_urgent_repeat_hours ١٢ — الافتراضي = الأرقام الثابتة الحالية، فلا يتغير شيء حتى يعدّلها المالك.
--     التعديل للمالك فقط (سياسة «Owner can update app_settings» كما هي). عتبة «منخفض» = ٠ تطفئ التنبيه.
--  ٥) sms_balance_status: «منخفض» حسب sms_low_threshold بدل ٥٠ الثابتة (نفس الشكل والصلاحية).
-- التراجع: supabase/rollback/20261020150000_kwtsms_daily_stats_rollback.sql (بعد تراجع 20261020151000 أولاً)
-- تجربة محلية: cd supabase/tests/family_links && node kwtsms_admin_stats.test.mjs

-- ٢) أعمدة جديدة (قيم مقيّدة — لا نصوص حرة من المزوّد)
alter table public.kwtsms_deliveries
  add column error_code text check (error_code ~ '^[A-Z0-9_]{1,32}$'),
  add column delivery_status text check (delivery_status ~ '^[A-Za-z0-9 _.:-]{1,40}$'),
  add column delivery_checked_at timestamptz,
  add column admin_test boolean not null default false;

-- ٤) عتبات التنبيه
alter table public.app_settings
  add column sms_low_threshold integer not null default 50
    check (sms_low_threshold between 0 and 100000),
  add column sms_urgent_threshold integer not null default 10,
  add column sms_low_repeat_hours integer not null default 24
    check (sms_low_repeat_hours between 1 and 168),
  add column sms_urgent_repeat_hours integer not null default 12
    check (sms_urgent_repeat_hours between 1 and 168),
  add constraint app_settings_sms_urgent_threshold_check
    check (sms_urgent_threshold between 0 and sms_low_threshold);

-- ١) السجل اليومي
create table public.kwtsms_daily_stats (
  day           date primary key,                -- بتوقيت الكويت (وقت حجز الإرسال)
  sends         integer not null default 0,      -- رموز دخول فعلية انتهت (بلا الوضع التجريبي ولا اختبار المالك)
  accepted      integer not null default 0,
  failed        integer not null default 0,
  unknown       integer not null default 0,
  test_sends    integer not null default 0,      -- الوضع التجريبي (test=1) + «اختبار إرسال لرقمي»
  points        numeric not null default 0,      -- النقاط المخصومة فعلاً (كل إرسال غير تجريبي، ومنه اختبار المالك)
  first_balance numeric,                         -- أول رصيد معروف في اليوم
  last_balance  numeric,                         -- آخر رصيد معروف في اليوم (من إرسال مقبول أو «تحديث الرصيد الآن»)
  balance_at    timestamptz,                     -- وقت last_balance
  updated_at    timestamptz not null default now()
);
alter table public.kwtsms_daily_stats enable row level security;
revoke all on public.kwtsms_daily_stats from public, anon, authenticated;

insert into public.kwtsms_daily_stats
  (day, sends, accepted, failed, unknown, test_sends, points, first_balance, last_balance, balance_at)
select (d.created_at at time zone 'Asia/Kuwait')::date,
       count(*) filter (where not d.test_mode),
       count(*) filter (where not d.test_mode and d.outcome = 'accepted'),
       count(*) filter (where not d.test_mode and d.outcome = 'failed'),
       count(*) filter (where not d.test_mode and d.outcome = 'unknown'),
       count(*) filter (where d.test_mode),
       coalesce(sum(d.points_charged) filter (where not d.test_mode), 0),
       (array_agg(d.balance_after order by d.created_at)
          filter (where d.outcome = 'accepted' and not d.test_mode and d.balance_after is not null))[1],
       (array_agg(d.balance_after order by d.created_at desc)
          filter (where d.outcome = 'accepted' and not d.test_mode and d.balance_after is not null))[1],
       max(d.created_at) filter (where d.outcome = 'accepted' and not d.test_mode and d.balance_after is not null)
  from public.kwtsms_deliveries d
 where d.outcome <> 'pending'
 group by 1;

-- ٣) finish_kwtsms_send: نفس السلوك + السجل اليومي + p_error_code + العتبات من app_settings
drop function public.finish_kwtsms_send(text, text, text, numeric, numeric);
create function public.finish_kwtsms_send(p_event text, p_outcome text, p_msgid text,
  p_charged numeric, p_balance numeric, p_error_code text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_urgent boolean;
  v_title  text;
  v_body   text;
  v_rows   int;
  v_at     timestamptz;
  v_test   boolean;
  v_admin  boolean;
  v_real   boolean;
  v_bal    numeric;
  v_low    int;
  v_crit   int;
  v_low_h  int;
  v_crit_h int;
begin
  update public.kwtsms_deliveries set outcome = p_outcome, provider_msgid = p_msgid,
    points_charged = p_charged, balance_after = p_balance,
    -- سبب الفشل فقط؛ قيمة غريبة تُهمل بدل ما تُفشل حفظ النتيجة
    error_code = case when p_outcome <> 'accepted' and p_error_code ~ '^[A-Z0-9_]{1,32}$' then p_error_code end
  where event_hash = p_event and outcome = 'pending'
  returning created_at, test_mode, admin_test into v_at, v_test, v_admin;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then return; end if;   -- حدث غير محجوز أو مُنهى من قبل: لا تنبيه

  -- السجل اليومي (بتوقيت الكويت). الوضع التجريبي واختبار المالك ← test_sends فقط، لا يدخلان نسبة القبول
  v_real := not v_test and not v_admin;
  v_bal  := case when p_outcome = 'accepted' and not v_test then p_balance end;
  insert into public.kwtsms_daily_stats as s
    (day, sends, accepted, failed, unknown, test_sends, points, first_balance, last_balance, balance_at)
  values ((v_at at time zone 'Asia/Kuwait')::date,
          case when v_real then 1 else 0 end,
          case when v_real and p_outcome = 'accepted' then 1 else 0 end,
          case when v_real and p_outcome = 'failed' then 1 else 0 end,
          case when v_real and p_outcome = 'unknown' then 1 else 0 end,
          case when v_real then 0 else 1 end,
          case when v_test then 0 else coalesce(p_charged, 0) end,
          v_bal, v_bal, case when v_bal is not null then v_at end)
  on conflict (day) do update set
    sends         = s.sends + excluded.sends,
    accepted      = s.accepted + excluded.accepted,
    failed        = s.failed + excluded.failed,
    unknown       = s.unknown + excluded.unknown,
    test_sends    = s.test_sends + excluded.test_sends,
    points        = s.points + excluded.points,
    first_balance = coalesce(s.first_balance, excluded.first_balance),
    last_balance  = case when excluded.balance_at >= coalesce(s.balance_at, '-infinity')
                         then excluded.last_balance else s.last_balance end,
    balance_at    = greatest(s.balance_at, excluded.balance_at),
    updated_at    = now();

  -- تنبيه الرصيد: بعد إرسال مقبول فقط، وتحت العتبة (الافتراضي ٥٠ نقطة)
  if p_outcome is distinct from 'accepted' or p_balance is null then
    return;
  end if;
  select a.sms_low_threshold, a.sms_urgent_threshold, a.sms_low_repeat_hours, a.sms_urgent_repeat_hours
    into v_low, v_crit, v_low_h, v_crit_h
    from public.app_settings a order by a.updated_at desc limit 1;
  v_low := coalesce(v_low, 50);  v_crit := coalesce(v_crit, 10);
  v_low_h := coalesce(v_low_h, 24);  v_crit_h := coalesce(v_crit_h, 12);
  if p_balance >= v_low then
    return;
  end if;
  v_urgent := p_balance < v_crit;
  -- ما نكرر: العادي مرة باليوم، والعاجل مرة كل ١٢ ساعة (المالك ٢٠٢٦-١٠-١٩) — الفواصل من app_settings
  if exists (
    select 1 from public.notifications n
     where n.kind = 'sms_balance_low'
       and n.created_at > now() - make_interval(hours => case when v_urgent then v_crit_h else v_low_h end)
       and (not v_urgent or n.title like '%عاجل%')
  ) then
    return;
  end if;
  v_title := case when v_urgent then 'عاجل: رصيد رسائل الدخول قارب يخلص' else 'رصيد رسائل الدخول قليل' end;
  v_body  := 'باقي ' || trim(to_char(p_balance, 'FM999999990')) || ' نقطة في KWT SMS — كل رمز دخول بنقطة. '
             || 'اشحن الرصيد حتى ما يوقف تسجيل الدخول.';
  insert into public.notifications (target_member_id, title, body, kind, created_by, is_read)
  select p.id, v_title, v_body, 'sms_balance_low', null, false
    from public.profiles p
   where p.role in ('owner', 'admin') and p.status = 'active';
end;
$$;
revoke all on function public.finish_kwtsms_send(text,text,text,numeric,numeric,text) from public, anon, authenticated;
grant execute on function public.finish_kwtsms_send(text,text,text,numeric,numeric,text) to service_role;

-- ٥) آخر رصيد معروف — «منخفض» حسب العتبة المحفوظة (للمالك والمدير فقط كما هو)
create or replace function public.sms_balance_status() returns jsonb
language plpgsql security definer set search_path = '' stable as $$
declare r record; v_low int;
begin
  if coalesce(public.current_user_role(), '') not in ('owner', 'admin') then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;
  select balance_after, created_at into r from public.kwtsms_deliveries
   where outcome = 'accepted' and balance_after is not null and not test_mode
   order by created_at desc limit 1;
  select a.sms_low_threshold into v_low from public.app_settings a order by a.updated_at desc limit 1;
  return jsonb_build_object('balance', r.balance_after, 'at', r.created_at,
                            'low', coalesce(r.balance_after < coalesce(v_low, 50), false));
end;
$$;
revoke all on function public.sms_balance_status() from public, anon;
grant execute on function public.sms_balance_status() to authenticated;
