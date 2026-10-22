-- SMS case details. The existing aggregate and its masked admin response stay compatible.
-- Only the owner can read per-request metadata. OTPs stay in private.login_codes
-- and are revealed exclusively by the existing, audited owner_reveal_login_code RPC.
alter table public.login_attempts add column if not exists sms_details jsonb not null default '{}'::jsonb
  check (jsonb_typeof(sms_details) = 'object');
create index if not exists login_attempts_msgid on public.login_attempts ((sms_details ->> 'msgid'))
  where sms_details ? 'msgid';

-- Hook-only writer: keep the existing retention and suspicious-attempt alerts.
-- currval is connection-local, so concurrent requests cannot attach metadata to
-- another attempt. All metadata is allowlisted; neither OTPs nor raw payloads persist.
create function public.log_sms_login_attempt(p_phone text, p_outcome text, p_details jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare v_id bigint; v_requested timestamptz; v_clean jsonb;
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
  v_clean := jsonb_strip_nulls(jsonb_build_object(
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

-- Preserve a queue check with the attempt even after the short provider ledger
-- expires. This is gateway status, never confirmation of receipt on a Kuwait handset.
create or replace function public.record_kwtsms_delivery_status(p_msgid text, p_status text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_found boolean; v_at timestamptz := clock_timestamp();
begin
  if p_msgid is null or p_msgid !~ '^[A-Za-z0-9-]{1,64}$'
     or p_status is null or p_status !~ '^[A-Za-z0-9 _.:-]{1,40}$' then
    raise exception 'Invalid delivery status';
  end if;
  update public.kwtsms_deliveries set delivery_status = p_status, delivery_checked_at = v_at
   where provider_msgid = p_msgid;
  v_found := found;
  update public.login_attempts
     set sms_details = sms_details || jsonb_build_object('queue_status', p_status, 'queue_checked_at', v_at)
   where sms_details ? 'msgid' and sms_details ->> 'msgid' = p_msgid;
  return v_found or found;
end;
$$;
revoke all on function public.record_kwtsms_delivery_status(text,text) from public, anon, authenticated;
grant execute on function public.record_kwtsms_delivery_status(text,text) to service_role;

-- Read a phone's SMS case, not the member profile. Every page is permission-checked.
-- The calendar window matches sms_login_attempts: Kuwait today + the preceding days.
create function public.owner_sms_login_details(p_phone text, p_days int default 7, p_before bigint default null)
returns jsonb language plpgsql security definer set search_path = '' stable as $$
declare
  v_phone text := regexp_replace(coalesce(p_phone, ''), '^(\+|00)', '');
  v_keep int; v_days int; v_from timestamptz; v_before_at timestamptz;
  v_items jsonb; v_total int; v_remaining int; v_next bigint; v_member jsonb; v_views jsonb; v_view_count int;
  v_summary jsonb; v_active_code jsonb;
  v_peak int; v_threshold int;
begin
  if coalesce(public.current_user_role(), '') <> 'owner' then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;
  if v_phone !~ '^965[4569][0-9]{7}$' then
    raise exception 'Invalid phone' using errcode = '22023';
  end if;
  select coalesce(a.login_attempts_retention_days, 30) into v_keep
    from public.app_settings a order by a.updated_at desc limit 1;
  v_keep := coalesce(v_keep, 30);
  v_days := least(greatest(coalesce(p_days, 7), 1), v_keep);
  v_from := (((now() at time zone 'Asia/Kuwait')::date) - (v_days - 1))::timestamp at time zone 'Asia/Kuwait';
  if p_before is not null then
    select a.created_at into v_before_at from public.login_attempts a where a.id = p_before and a.phone = v_phone;
    if not found then raise exception 'Invalid cursor' using errcode = '22023'; end if;
  end if;

  select jsonb_build_object('id', p.id,
    'name', coalesce(nullif(btrim(p.full_name), ''), nullif(btrim(p.first_name), '')),
    'status', p.status)
    into v_member from public.profiles p where p.id = public.login_attempt_profile_id(v_phone);
  select count(*) into v_total from public.login_attempts a where a.phone = v_phone and a.created_at >= v_from;
  select coalesce(max(x.n), 0) into v_peak from (select count(*) n from public.login_attempts a
    where a.phone = v_phone and a.created_at >= v_from group by date_trunc('hour', a.created_at)) x;
  v_threshold := public.config_int('sms_suspicious_per_hour', 5);
  select jsonb_build_object('phone', '+965 ' || substr(v_phone, 4), 'phone_e164', '+' || v_phone,
    'name', v_member ->> 'name', 'profile_id', v_member ->> 'id', 'member_status', v_member ->> 'status',
    'is_member', v_member is not null, 'attempts_in_window', count(*),
    'max_in_hour', v_peak, 'suspicious', v_peak >= v_threshold,
    'attempts_today', count(*) filter (where a.created_at >= (now() at time zone 'Asia/Kuwait')::date::timestamp at time zone 'Asia/Kuwait'),
    'sent', count(*) filter (where a.outcome = 'sent'), 'failed', count(*) filter (where a.outcome = 'failed'),
    'blocked', count(*) filter (where a.outcome = 'blocked'), 'unknown', count(*) filter (where a.outcome = 'unknown'),
    'test', count(*) filter (where a.outcome = 'test'), 'first_at', min(a.created_at), 'last_at', max(a.created_at),
    'last_outcome', (array_agg(a.outcome order by a.created_at desc, a.id desc))[1],
    'last_sign_in_at', (select max(u.last_sign_in_at) from auth.users u where u.phone = v_phone),
    'logged_in', coalesce((select max(u.last_sign_in_at) from auth.users u where u.phone = v_phone) >= min(a.created_at), false))
    into v_summary from public.login_attempts a where a.phone = v_phone and a.created_at >= v_from;
  select jsonb_build_object('sent_at', c.sent_at, 'expires_at', c.expires_at) into v_active_code
    from private.login_codes c where c.phone = v_phone and private.login_code_valid(c.phone, c.sent_at, c.expires_at);
  select count(*) into v_remaining from public.login_attempts a
   where a.phone = v_phone and a.created_at >= v_from
     and (p_before is null or (a.created_at, a.id) < (v_before_at, p_before));
  select coalesce(jsonb_agg(x.j order by x.created_at desc, x.id desc), '[]'::jsonb) into v_items
    from (select a.id, a.created_at, jsonb_build_object('id', a.id, 'recorded_at', a.created_at,
      'outcome', a.outcome, 'alerted', a.alerted, 'details', a.sms_details) j
      from public.login_attempts a where a.phone = v_phone and a.created_at >= v_from
        and (p_before is null or (a.created_at, a.id) < (v_before_at, p_before))
      order by a.created_at desc, a.id desc limit 50) x;
  if v_remaining > 50 then
    v_next := (v_items -> (jsonb_array_length(v_items) - 1) ->> 'id')::bigint;
  end if;

  select count(*) into v_view_count from private.login_code_views v where v.phone = v_phone and v.viewed_at >= v_from;
  select coalesce(jsonb_agg(x.j order by x.viewed_at desc, x.id desc), '[]'::jsonb) into v_views
    from (select v.id, v.viewed_at, jsonb_build_object('id', v.id, 'at', v.viewed_at, 'result', v.result,
      'by', coalesce(nullif(btrim(p.full_name), ''), nullif(btrim(p.first_name), ''))) j
      from private.login_code_views v left join public.profiles p on p.id = v.viewed_by
      where v.phone = v_phone and v.viewed_at >= v_from order by v.viewed_at desc, v.id desc limit 20) x;
  return jsonb_build_object('phone_e164', '+' || v_phone, 'days', v_days, 'from', v_from,
    'generated_at', now(), 'retention_days', v_keep, 'member', v_member,
    'last_sign_in_at', (select max(u.last_sign_in_at) from auth.users u where u.phone = v_phone),
    'summary', v_summary, 'active_code', v_active_code,
    'total', v_total, 'items', v_items, 'next_before', v_next, 'code_views', v_views, 'code_view_count', v_view_count);
end;
$$;
revoke all on function public.owner_sms_login_details(text,int,bigint) from public, anon;
grant execute on function public.owner_sms_login_details(text,int,bigint) to authenticated;

notify pgrst, 'reload schema';
