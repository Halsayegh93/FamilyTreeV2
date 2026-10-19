-- تنبيه رصيد KWT SMS العاجل (تحت ١٠ نقاط): كل ١٢ ساعة بدل ٣ ساعات (طلب المالك ٢٠٢٦-١٠-١٩
-- «اذا نزل اقل من ١٠ خله كل ١٢ ساعة»). باقي التنبيه كما هو (تحت ٥٠: مرة باليوم).
-- التراجع: supabase/rollback/20261019230000_kwtsms_urgent_alert_12h_rollback.sql (يرجّع ٣ ساعات)
create or replace function public.finish_kwtsms_send(p_event text, p_outcome text, p_msgid text,
  p_charged numeric, p_balance numeric) returns void
language plpgsql security definer set search_path = '' as $$
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
$$;
revoke all on function public.finish_kwtsms_send(text,text,text,numeric,numeric) from public, anon, authenticated;
grant execute on function public.finish_kwtsms_send(text,text,text,numeric,numeric) to service_role;

