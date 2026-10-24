-- تراجع 20261023100000_kwtsms_request_lock — يعيد reserve_kwtsms_send كما كانت على الحي حرفياً (md5 ada5bf5d…)،
-- ويحذف جدولي السجل والقفل وقيم الحماية الأربع (إن لم يغيّرها المالك).
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

drop table if exists public.kwtsms_number_locks;
drop table if exists public.kwtsms_request_log;
delete from public.app_config
 where key in ('sms_lock_requests', 'sms_lock_window_minutes', 'sms_lock_minutes', 'sms_daily_per_number')
   and updated_by is null;
