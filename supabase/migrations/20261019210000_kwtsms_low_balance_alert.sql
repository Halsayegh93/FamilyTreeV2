-- تنبيه رصيد KWT SMS (موافقة المالك ٢٠٢٦-١٠-١٩ «نعم» على «تنبيه الرصيد»)
-- الرصيد يرجع مع كل رسالة (balance-after) وينحفظ في kwtsms_deliveries عبر finish_kwtsms_send — فالتنبيه هنا بلا
-- أي طلب زيادة لـ KWT SMS:
--   • الرصيد < ٥٠ نقطة  ← إشعار للمالك والمدراء المفعّلين، مرة باليوم بالكثير
--   • الرصيد < ١٠ نقاط ← إشعار عاجل، مرة كل ٣ ساعات بالكثير، لين ينشحن
-- النوع sms_balance_low (الدفع يمر بـ push-on-notification وتفضيلات الإشعارات كالعادة).
-- + sms_balance_status(): آخر رصيد معروف ووقته — للمالك والمدير فقط (لعرضه لاحقاً في «صحة النظام»).
-- لا أرقام هواتف ولا رموز تُحفظ (كما هو). التراجع: supabase/rollback/20261019210000_kwtsms_low_balance_alert_rollback.sql
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
  -- ما نكرر: العادي مرة باليوم، والعاجل مرة كل ٣ ساعات
  if exists (
    select 1 from public.notifications n
     where n.kind = 'sms_balance_low'
       and n.created_at > now() - case when v_urgent then interval '3 hours' else interval '24 hours' end
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

-- آخر رصيد معروف (من آخر إرسال مقبول) — للمالك والمدير فقط
create or replace function public.sms_balance_status() returns jsonb
language plpgsql security definer set search_path = '' stable as $$
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
$$;
revoke all on function public.sms_balance_status() from public, anon;
grant execute on function public.sms_balance_status() to authenticated;
