-- رسائل الدخول · حماية الطلبات (طلب المالك ٢٠٢٦-١٠-٢٣ «سو ١ و ٢»): يوم ٢٢ أكتوبر طلب برنامج آلي (نسخة آيفون قديمة ١٩
-- من مركز بيانات) رمزاً لرقم المالك ١٢ مرة في ٩٠ ثانية، فوصلته رسالتان.
--  ١) قفل الطلبات المتكررة: ٦ طلبات للرقم نفسه خلال ١٠ دقائق (حتى المرفوضة) ← قفل ٣٠ دقيقة بلا أي رسالة.
--  ٢) حد يومي: أقصى ٦ رسائل لكل رقم خلال ٢٤ ساعة.
--  ٣) إشعار للمالك مرة واحدة عند قفل أي رقم.
--  الأرقام قيم في app_config (قسم الرسائل) يعدّلها المالك بلا نسخة جديدة.
--  الدالة الطرفية send-sms-kwtsms لا تتغيّر (جلسة أخرى تملكها، النسخة ٢٤): الحماية داخل reserve_kwtsms_send وحدها،
--  وردّها كما هو («blocked:<ثوانٍ>» للنسخ الجديدة) فتعرض التطبيقات «انتظر …» كالعادة.
--  البصمة فقط (phone_hash) — لا رقم صريح في الجدولين الجديدين، والسجل يُحذف بعد يومين.
-- التراجع: supabase/rollback/20261023100000_kwtsms_request_lock_rollback.sql (يعيد الدالة الحية حرفياً، md5 ada5bf5d…)

create table public.kwtsms_request_log (
  id         bigserial primary key,
  phone_hash text not null check (phone_hash ~ '^[a-f0-9]{64}$'),
  created_at timestamptz not null default clock_timestamp()
);
create index kwtsms_request_log_phone_time on public.kwtsms_request_log (phone_hash, created_at);
create index kwtsms_request_log_time on public.kwtsms_request_log (created_at);
alter table public.kwtsms_request_log enable row level security;
revoke all on public.kwtsms_request_log from public, anon, authenticated;
revoke all on sequence public.kwtsms_request_log_id_seq from public, anon, authenticated;

create table public.kwtsms_number_locks (
  phone_hash   text primary key check (phone_hash ~ '^[a-f0-9]{64}$'),
  locked_until timestamptz not null,
  locked_at    timestamptz not null default clock_timestamp()
);
alter table public.kwtsms_number_locks enable row level security;
revoke all on public.kwtsms_number_locks from public, anon, authenticated;

insert into public.app_config (key, kind, value, default_value, min_value, max_value, max_length, category,
                               label_ar, help_ar, rules, is_public, sort)
values
  ('sms_lock_requests', 'int', '6', '6', 3, 30, null, 'sms', 'قفل الرقم بعد (طلبات)',
   'إذا انطلب رمز لنفس الرقم هذا العدد من المرات خلال المدة التالية — حتى لو انرفضت — يتقفل الرقم.', '{}', false, 60),
  ('sms_lock_window_minutes', 'int', '10', '10', 1, 60, null, 'sms', 'خلال (دقائق)',
   'المدة التي تُعدّ فيها الطلبات المتكررة لنفس الرقم.', '{}', false, 61),
  ('sms_lock_minutes', 'int', '30', '30', 5, 1440, null, 'sms', 'مدة القفل (دقائق)',
   'كم دقيقة يبقى الرقم مقفولاً بلا أي رسالة رمز بعد الطلبات المتكررة.', '{}', false, 62),
  ('sms_daily_per_number', 'int', '6', '6', 1, 50, null, 'sms', 'أقصى رسائل للرقم باليوم',
   'أقصى عدد رسائل رمز الدخول لنفس الرقم خلال ٢٤ ساعة.', '{}', false, 63)
on conflict (key) do nothing;

CREATE OR REPLACE FUNCTION public.reserve_kwtsms_send(p_event text, p_phone text, p_test boolean, p_format integer DEFAULT 1)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_now timestamptz := clock_timestamp(); v_existing text;
  v_wait int; v_per_number int; v_all_hour int; v_sender text;
  v_at timestamptz; v_left numeric := 0;
  v_tpl text; v_tpl_en text;
  v_lock_n int; v_lock_window int; v_lock_minutes int; v_daily int; v_lock_until timestamptz;
begin
  if p_event !~ '^[a-f0-9]{64}$' or p_phone !~ '^[a-f0-9]{64}$' or p_test is null then
    raise exception 'Invalid reservation';
  end if;
  -- Serializes short reservations across Edge instances; never held during a provider call.
  perform pg_advisory_xact_lock(19200000, 1);
  delete from public.kwtsms_deliveries where created_at < v_now - interval '2 days';
  select outcome into v_existing from public.kwtsms_deliveries where event_hash = p_event;
  if found then return case when v_existing = 'accepted' then 'accepted' else 'blocked' end; end if;
  -- ═══ حماية الطلبات (20261023100000، طلب المالك ٢٠٢٦-١٠-٢٣ بعد ١٢ طلباً آلياً لرقمه في دقيقة ونصف) ═══
  -- ١) قفل الطلبات المتكررة: كل طلب يُسجَّل (بصمة الرقم فقط)؛ N طلب خلال W دقيقة ← قفل L دقيقة بلا إرسال.
  -- ٢) حد يومي: أقصى D رسالة لكل رقم خلال ٢٤ ساعة.
  -- الأرقام من app_config («قيم التطبيق»، يعدّلها المالك)؛ أي خلل في القراءة ← الافتراضي.
  begin
    v_lock_n := public.config_int('sms_lock_requests', 6);
    v_lock_window := public.config_int('sms_lock_window_minutes', 10);
    v_lock_minutes := public.config_int('sms_lock_minutes', 30);
    v_daily := public.config_int('sms_daily_per_number', 6);
  exception when others then
    v_lock_n := 6;  v_lock_window := 10;  v_lock_minutes := 30;  v_daily := 6;
  end;
  v_lock_n := greatest(coalesce(v_lock_n, 6), 2);  v_lock_window := greatest(coalesce(v_lock_window, 10), 1);
  v_lock_minutes := greatest(coalesce(v_lock_minutes, 30), 1);  v_daily := greatest(coalesce(v_daily, 6), 1);
  insert into public.kwtsms_request_log (phone_hash, created_at) values (p_phone, v_now);
  delete from public.kwtsms_request_log
   where id in (select r.id from public.kwtsms_request_log r
                 where r.created_at < v_now - interval '2 days' order by r.created_at limit 200);
  select l.locked_until into v_lock_until from public.kwtsms_number_locks l
   where l.phone_hash = p_phone and l.locked_until > v_now;
  if v_lock_until is null
     and (select count(*) from public.kwtsms_request_log r
           where r.phone_hash = p_phone and r.created_at > v_now - make_interval(mins => v_lock_window)) >= v_lock_n then
    v_lock_until := v_now + make_interval(mins => v_lock_minutes);
    insert into public.kwtsms_number_locks (phone_hash, locked_until, locked_at)
    values (p_phone, v_lock_until, v_now)
    on conflict (phone_hash) do update set locked_until = excluded.locked_until, locked_at = excluded.locked_at;
    -- ٣) إشعار للمالك مرة واحدة عند القفل (نوع sms_suspicious ← «طلبات رمز الدخول» حيث الرقم كاملاً) — بأفضل جهد
    begin
      insert into public.notifications (target_member_id, title, body, kind, created_by, is_read)
      select p.id, 'تقفل رقم بسبب طلبات متكررة',
             'انطلب رمز الدخول ' || v_lock_n || ' مرات خلال ' || v_lock_window || ' دقائق لرقم واحد، فتقفل '
             || v_lock_minutes || ' دقيقة بلا رسائل. الرقم في «طلبات رمز الدخول».',
             'sms_suspicious', null, false
        from public.profiles p where p.role = 'owner' and p.status = 'active';
    exception when others then
      raise warning 'reserve_kwtsms_send: lock notice skipped (%)', sqlstate;
    end;
  end if;
  if v_lock_until is not null then
    v_left := greatest(v_left, extract(epoch from (v_lock_until - v_now)));
  end if;
  select d.created_at into v_at from public.kwtsms_deliveries d
   where d.phone_hash = p_phone and d.created_at > v_now - interval '24 hours'
   order by d.created_at desc offset v_daily - 1 limit 1;
  if v_at is not null then
    v_left := greatest(v_left, extract(epoch from (v_at + interval '24 hours' - v_now)));
  end if;
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
  -- p_format ٣ (الدالة الطرفية بعد 20261021120000): رد JSON فيه المرسل المحفوظ ونص رسالة الرمز من app_config
  -- (الدالة الطرفية تتحقق من الاثنين وتعود لنصها المدمج لأي خلل). قراءة النص بأفضل جهد: أي خطأ ← null، والحجز يبقى.
  if coalesce(p_format, 1) >= 3 then
    begin
      v_tpl := public.config_text('sms_otp_template', null);
      v_tpl_en := public.config_text('sms_otp_template_en', null);
    exception when others then
      v_tpl := null;  v_tpl_en := null;
    end;
    return jsonb_build_object('action', 'send',
      'sender', case when v_sender ~ '^[A-Za-z0-9 -]{1,11}$' then v_sender end,
      'template', v_tpl, 'template_en', v_tpl_en)::text;
  end if;
  -- الرد المفصّل: المرسل المحفوظ إن وُجد (الدالة الطرفية تتحقق منه مرة ثانية)؛ الرد القديم «send» حرفياً
  if coalesce(p_format, 1) >= 2 and v_sender ~ '^[A-Za-z0-9 -]{1,11}$' then
    return 'send:' || v_sender;
  end if;
  return 'send';
end;
$function$;
