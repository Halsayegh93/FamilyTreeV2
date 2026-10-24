-- تراجع 20261019210000: يرجّع finish_kwtsms_send كما كانت (بلا تنبيه) ويحذف sms_balance_status
create or replace function public.finish_kwtsms_send(p_event text,p_outcome text,p_msgid text,
  p_charged numeric,p_balance numeric) returns void
language sql security definer set search_path = '' as $$
  update public.kwtsms_deliveries set outcome=p_outcome,provider_msgid=p_msgid,
    points_charged=p_charged,balance_after=p_balance
  where event_hash=p_event and outcome='pending';
$$;
revoke all on function public.finish_kwtsms_send(text,text,text,numeric,numeric) from public,anon,authenticated;
grant execute on function public.finish_kwtsms_send(text,text,text,numeric,numeric) to service_role;
drop function if exists public.sms_balance_status();
