-- تراجع 20261020150000 (بعد تراجع 20261020151000): يرجّع finish_kwtsms_send و sms_balance_status كما هي على السيرفر
-- الحي حرفياً (pg_get_functiondef ٢٠٢٦-١٠-٢٠، md5 252b46e5… و 31ce0e27… — تتحقق منه التجربة المحلية)، ويحذف السجل
-- اليومي (تضيع أرقام ٧/٣٠ يوماً المحفوظة فيه) والأعمدة الجديدة (سبب الفشل، حالة الوصول، علامة اختبار المالك)
-- وعتبات التنبيه من app_settings. الدالة المنشورة send-sms-kwtsms القديمة تعمل بعده كما هي؛ النسخة الجديدة التي
-- ترسل p_error_code تفشل في حفظ نتيجة الإرسال الفاشل فقط (الدخول نفسه لا يتأثر) — رجّعها للنسخة السابقة معه.
drop function if exists public.finish_kwtsms_send(text, text, text, numeric, numeric, text);
CREATE OR REPLACE FUNCTION public.finish_kwtsms_send(p_event text, p_outcome text, p_msgid text, p_charged numeric, p_balance numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_urgent boolean;
  v_title  text;
  v_body   text;
  v_rows   int;
begin
  update public.kwtsms_deliveries set outcome = p_outcome, provider_msgid = p_msgid,
    points_charged = p_charged, balance_after = p_balance
  where event_hash = p_event and outcome = 'pending';
  get diagnostics v_rows = row_count;
  if v_rows = 0 then return; end if;   -- حدث غير محجوز أو مُنهى من قبل: لا تنبيه

  -- تنبيه الرصيد: بعد إرسال مقبول فقط، وتحت ٥٠ نقطة
  if p_outcome is distinct from 'accepted' or p_balance is null or p_balance >= 50 then
    return;
  end if;
  v_urgent := p_balance < 10;
  -- ما نكرر: العادي مرة باليوم، والعاجل مرة كل ١٢ ساعة (المالك ٢٠٢٦-١٠-١٩)
  if exists (
    select 1 from public.notifications n
     where n.kind = 'sms_balance_low'
       and n.created_at > now() - case when v_urgent then interval '12 hours' else interval '24 hours' end
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
$function$;
revoke all on function public.finish_kwtsms_send(text,text,text,numeric,numeric) from public, anon, authenticated;
grant execute on function public.finish_kwtsms_send(text,text,text,numeric,numeric) to service_role;

CREATE OR REPLACE FUNCTION public.sms_balance_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record;
begin
  if coalesce(public.current_user_role(), '') not in ('owner', 'admin') then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;
  select balance_after, created_at into r from public.kwtsms_deliveries
   where outcome = 'accepted' and balance_after is not null and not test_mode
   order by created_at desc limit 1;
  return jsonb_build_object('balance', r.balance_after, 'at', r.created_at,
                            'low', coalesce(r.balance_after < 50, false));
end;
$function$;

drop table if exists public.kwtsms_daily_stats;
alter table public.kwtsms_deliveries
  drop column if exists error_code,
  drop column if exists delivery_status,
  drop column if exists delivery_checked_at,
  drop column if exists admin_test;
alter table public.app_settings
  drop constraint if exists app_settings_sms_urgent_threshold_check,
  drop column if exists sms_low_threshold,
  drop column if exists sms_urgent_threshold,
  drop column if exists sms_low_repeat_hours,
  drop column if exists sms_urgent_repeat_hours;
