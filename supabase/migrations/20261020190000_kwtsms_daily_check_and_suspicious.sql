-- رسائل الدخول · KWT SMS — فحص الرصيد اليومي + تنبيه المحاولات المريبة (موافقة المالك ٢٠٢٦-١٠-٢٠، الميزتان ٣ و٤).
-- مُعدّ ولم يُطبَّق. يحتاج قبله 20261019200000…20261020180000 (كلها على الحي).
--
-- ٣) فحص الرصيد اليومي — اليوم ينبّه الرصيد فقط بعد إرسال ناجح (finish_kwtsms_send)، فلو ما أحد دخل والرصيد نازل
--    ما يدري أحد. الآن كل يوم ٠٩:٠٠ بتوقيت الكويت (٠٦:٠٠ UTC؛ cron.timezone = GMT على الحي):
--    pg_cron «kwtsms-daily-balance» ← kwtsms_daily_balance_job() ← net.http_post للدالة الطرفية kwtsms-cron بترويسة
--    x-webhook-secret = private.app_secrets «push_webhook_secret» — نفس السرّ ونفس نمط trigger_push_on_notification
--    (الدالة الطرفية تقارنه بـ PUSH_WEBHOOK_SECRET الموجود). لا سرّ جديد.
--    kwtsms-cron تقرأ الرصيد الحي من KWT ثم تستدعي kwtsms_balance_check(p_balance) (service_role فقط):
--      • يحفظه بـ record_kwtsms_balance (السجل اليومي، كـ«تحديث الرصيد الآن») — فيظهر حتى في يوم بلا رسائل.
--      • نفس قواعد تنبيه finish_kwtsms_send حرفياً: تحت sms_low_threshold ← «رصيد رسائل الدخول قليل» مرة كل
--        sms_low_repeat_hours؛ تحت sms_urgent_threshold ← «عاجل: …» مرة كل sms_urgent_repeat_hours؛ نفس النوع
--        sms_balance_low ونفس النص ونفس المستلمين (المالك والمدراء المفعّلون). التكرار يُفحص على نفس الإشعارات،
--        فتنبيه بعد إرسال يمنع تنبيه الفحص داخل الفاصل والعكس. عتبة «منخفض» = ٠ تطفئه (كما هو).
--      • فشل KWT ← الدالة الطرفية ما تستدعي شيئاً: لا حفظ ولا تنبيه. بلا إعادة محاولة.
--    finish_kwtsms_send لا تُلمس.
--
-- ٤) تنبيه المحاولات المريبة — log_login_attempt: نفس السلوك حرفياً (التحقق، المطابقة، الإدراج، الحذف المحدود) ثم:
--    لو للرقم ٥ محاولات أو أكثر (أي نتيجة — نفس تعريف «مريب» في صفحة «محاولات الدخول») خلال آخر ٦٠ دقيقة، ولم يُنبَّه
--    عنه خلال آخر ١٢ ساعة ← إشعار للمالك والمدراء المفعّلين، النوع sms_suspicious، العنوان «محاولات دخول مريبة»،
--    النص «{الاسم أو رقم غير مسجّل} طلب رمز الدخول N مرات خلال ساعة — {الرقم}»: المالك يرى الرقم كاملاً
--    «+965 90031265»، المدير مخفياً «+965 9003••65» (نفس إخفاء sms_login_attempts). بلا details (مثل sms_balance_low).
--    «لم يُنبَّه خلال ١٢ ساعة» = عمود جديد login_attempts.alerted (المحاولة التي أطلقت التنبيه) — لا يعتمد على بقاء
--    الإشعار (العضو يحذف إشعاراته) ولا يضع الرقم في الإشعارات. الجزء كله في كتلة استثناء: أي خطأ يُبلع (يتراجع التنبيه
--    وحده والمحاولة محفوظة)، وقفل استشاري غير منتظِر لكل رقم يمنع تنبيهين متزامنين بلا أي انتظار.
--    الحد ثابت ٥ (= «مريب» في الصفحة). الإشعار يمر بالدفع وتفضيلات الإشعارات كالعادة (الفئة admin_activity).
--
-- التراجع: supabase/rollback/20261020190000_kwtsms_daily_check_and_suspicious_rollback.sql
-- تجربة محلية: cd supabase/tests/family_links && node kwtsms_daily_check.test.mjs

-- ═══ ٣-أ) الحفظ + قواعد تنبيه الرصيد (kwtsms-cron فقط) ═══
create function public.kwtsms_balance_check(p_balance numeric) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_urgent boolean;
  v_title  text;
  v_body   text;
  v_low    int;
  v_crit   int;
  v_low_h  int;
  v_crit_h int;
  v_state  text;
  v_sent   int;
begin
  -- نفس تحقق وحفظ «تحديث الرصيد الآن» (قيمة غير صالحة ← «Invalid balance» ولا شيء يُحفظ)
  perform public.record_kwtsms_balance(p_balance);

  -- من هنا: نفس قواعد finish_kwtsms_send حرفياً (العتبات والفواصل من app_settings)
  select a.sms_low_threshold, a.sms_urgent_threshold, a.sms_low_repeat_hours, a.sms_urgent_repeat_hours
    into v_low, v_crit, v_low_h, v_crit_h
    from public.app_settings a order by a.updated_at desc limit 1;
  v_low := coalesce(v_low, 50);  v_crit := coalesce(v_crit, 10);
  v_low_h := coalesce(v_low_h, 24);  v_crit_h := coalesce(v_crit_h, 12);
  if p_balance >= v_low then
    return jsonb_build_object('recorded', true, 'state', 'ok', 'alerted', false);
  end if;
  v_urgent := p_balance < v_crit;
  v_state := case when v_urgent then 'urgent' else 'low' end;
  if exists (
    select 1 from public.notifications n
     where n.kind = 'sms_balance_low'
       and n.created_at > now() - make_interval(hours => case when v_urgent then v_crit_h else v_low_h end)
       and (not v_urgent or n.title like '%عاجل%')
  ) then
    return jsonb_build_object('recorded', true, 'state', v_state, 'alerted', false);
  end if;
  v_title := case when v_urgent then 'عاجل: رصيد رسائل الدخول قارب يخلص' else 'رصيد رسائل الدخول قليل' end;
  v_body  := 'باقي ' || trim(to_char(p_balance, 'FM999999990')) || ' نقطة في KWT SMS — كل رمز دخول بنقطة. '
             || 'اشحن الرصيد حتى ما يوقف تسجيل الدخول.';
  insert into public.notifications (target_member_id, title, body, kind, created_by, is_read)
  select p.id, v_title, v_body, 'sms_balance_low', null, false
    from public.profiles p
   where p.role in ('owner', 'admin') and p.status = 'active';
  get diagnostics v_sent = row_count;
  return jsonb_build_object('recorded', true, 'state', v_state, 'alerted', v_sent > 0);
end;
$$;
revoke all on function public.kwtsms_balance_check(numeric) from public, anon, authenticated;
grant execute on function public.kwtsms_balance_check(numeric) to service_role;

-- ═══ ٣-ب) نداء الدالة الطرفية (مهمة pg_cron فقط — لا تنفيذ للتطبيقات ولا للخدمة) ═══
-- نفس نمط trigger_push_on_notification: السرّ من private.app_secrets، الرابط ثابت، نداء غير متزامن (pg_net).
-- تشغيل يدوي للتجربة بعد النشر: select public.kwtsms_daily_balance_job();  ثم net._http_response بالرقم الراجع.
create function public.kwtsms_daily_balance_job() returns bigint
language plpgsql security definer set search_path = '' as $$
declare v_secret text;
begin
  select s.value into v_secret from private.app_secrets s where s.key = 'push_webhook_secret';
  if coalesce(v_secret, '') = '' then
    raise warning 'kwtsms_daily_balance_job: push_webhook_secret missing';
    return null;
  end if;
  return net.http_post(
    url := 'https://poxyxsgvzwmnmewytsiw.supabase.co/functions/v1/kwtsms-cron'::text,
    body := jsonb_build_object('action', 'balance_check'),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', v_secret),
    timeout_milliseconds := 20000
  );
end;
$$;
revoke all on function public.kwtsms_daily_balance_job() from public, anon, authenticated, service_role;

-- ═══ ٤-أ) من أطلق التنبيه (لمنع التكرار ١٢ ساعة) ═══
alter table public.login_attempts add column alerted boolean not null default false;

-- ═══ ٤-ب) تسجيل المحاولة + تنبيه المحاولات المريبة ═══
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

-- ═══ ٣-ج) الجدولة: ٠٦:٠٠ UTC = ٠٩:٠٠ الكويت — cron.schedule بالاسم نفسه يحدّث المهمة بدل تكرارها ═══
select cron.schedule('kwtsms-daily-balance', '0 6 * * *', 'select public.kwtsms_daily_balance_job()');
