-- Keep recorded SMS metadata; rollback must not erase the audit history.
-- The updated hook falls back to log_login_attempt when its new RPC is absent.
drop function if exists public.owner_sms_login_details(text,int,bigint);
drop function if exists public.log_sms_login_attempt(text,text,jsonb);
create or replace function public.record_kwtsms_delivery_status(p_msgid text, p_status text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if p_msgid is null or p_msgid !~ '^[A-Za-z0-9-]{1,64}$'
     or p_status is null or p_status !~ '^[A-Za-z0-9 _.:-]{1,40}$' then
    raise exception 'Invalid delivery status';
  end if;
  update public.kwtsms_deliveries set delivery_status = p_status, delivery_checked_at = clock_timestamp()
   where provider_msgid = p_msgid;
  return found;
end;
$$;
revoke all on function public.record_kwtsms_delivery_status(text,text) from public, anon, authenticated;
grant execute on function public.record_kwtsms_delivery_status(text,text) to service_role;
notify pgrst, 'reload schema';
