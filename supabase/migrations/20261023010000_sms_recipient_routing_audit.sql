-- Auth's SMS recipient can differ from user.phone (phone change / MFA).
-- Record the selected recipient source, purpose and signed Auth origin.
-- The phone remains the SMS destination, never proof that its owner requested it.
-- Keep the existing writer contract, service-only ACL, retention and alerts.
create or replace function public.log_sms_login_attempt(p_phone text, p_outcome text, p_details jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare v_id bigint; v_requested timestamptz; v_clean jsonb; v_ip text;
begin
  if p_details is null or jsonb_typeof(p_details) <> 'object' then
    raise exception 'Invalid SMS details' using errcode = '22023';
  end if;
  begin
    v_requested := (p_details ->> 'requested_at')::timestamptz;
  exception when others then v_requested := null;
  end;
  if v_requested is not null and (v_requested < now() - interval '1 hour' or v_requested > now() + interval '1 minute') then
    v_requested := null;
  end if;
  -- Signed Auth origin only. Invalid optional metadata never blocks a real OTP.
  begin
    if p_details ->> 'source_ip' ~ '^[0-9A-Fa-f:.]{2,45}$' then
      v_ip := host((p_details ->> 'source_ip')::inet);
    end if;
  exception when others then v_ip := null;
  end;
  v_clean := jsonb_strip_nulls(jsonb_build_object(
    'source_ip', v_ip,
    'hook_id', case when p_details ->> 'hook_id' ~* '^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$' then lower(p_details ->> 'hook_id') end,
    'sms_kind', case when p_details ->> 'sms_kind' in ('login_or_signup','phone_change','mfa','reauthentication','verification') then p_details ->> 'sms_kind' end,
    'recipient_source', case when p_details ->> 'recipient_source' in ('sms_phone','legacy_user_phone') then p_details ->> 'recipient_source' end,
    'requested_at', v_requested,
    'msgid', case when p_details ->> 'msgid' ~ '^[A-Za-z0-9-]{1,64}$' then p_details ->> 'msgid' end,
    'error_code', case when p_details ->> 'error_code' ~ '^[A-Z0-9_]{1,32}$' then p_details ->> 'error_code' end,
    'sender', case when p_details ->> 'sender' ~ '^[A-Za-z0-9 -]{1,11}$' then p_details ->> 'sender' end,
    'test_mode', case when jsonb_typeof(p_details -> 'test_mode') = 'boolean' then p_details -> 'test_mode' end,
    'http_status', case when p_details ->> 'http_status' ~ '^[1-5][0-9]{2}$' then (p_details ->> 'http_status')::int end,
    'retry_after_seconds', case when p_details ->> 'retry_after_seconds' ~ '^[0-9]{1,4}$'
      then least((p_details ->> 'retry_after_seconds')::int, 3600) end,
    'points', case when jsonb_typeof(p_details -> 'points') = 'number' then
      case when (p_details ->> 'points')::numeric between 0 and 100000000 then p_details -> 'points' end end,
    'balance_after', case when jsonb_typeof(p_details -> 'balance_after') = 'number' then
      case when (p_details ->> 'balance_after')::numeric between 0 and 100000000 then p_details -> 'balance_after' end end));
  perform public.log_login_attempt(p_phone, p_outcome);
  v_id := pg_catalog.currval('public.login_attempts_id_seq');
  update public.login_attempts set sms_details = v_clean where id = v_id and phone = p_phone;
end;
$$;
revoke all on function public.log_sms_login_attempt(text,text,jsonb) from public, anon, authenticated;
grant execute on function public.log_sms_login_attempt(text,text,jsonb) to service_role;

notify pgrst, 'reload schema';
