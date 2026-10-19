-- No phone numbers, OTPs or credentials are persisted. HMAC keys stay in Edge Secrets.
begin;
create table public.kwtsms_deliveries (
  event_hash text primary key check (event_hash ~ '^[a-f0-9]{64}$'),
  phone_hash text not null check (phone_hash ~ '^[a-f0-9]{64}$'),
  created_at timestamptz not null default clock_timestamp(),
  test_mode boolean not null,
  outcome text not null default 'pending' check (outcome in ('pending','accepted','failed','unknown')),
  provider_msgid text,
  points_charged numeric,
  balance_after numeric
);
create index kwtsms_phone_time on public.kwtsms_deliveries(phone_hash, created_at desc);
create index kwtsms_created_time on public.kwtsms_deliveries(created_at);
alter table public.kwtsms_deliveries enable row level security;
revoke all on public.kwtsms_deliveries from public, anon, authenticated;

create function public.reserve_kwtsms_send(p_event text, p_phone text, p_test boolean)
returns text language plpgsql security definer set search_path = '' as $$
declare v_now timestamptz := clock_timestamp(); v_existing text;
begin
  if p_event !~ '^[a-f0-9]{64}$' or p_phone !~ '^[a-f0-9]{64}$' or p_test is null then
    raise exception 'Invalid reservation';
  end if;
  -- Serializes short reservations across Edge instances; never held during a provider call.
  perform pg_advisory_xact_lock(19200000, 1);
  delete from public.kwtsms_deliveries where created_at < v_now - interval '2 days';
  select outcome into v_existing from public.kwtsms_deliveries where event_hash = p_event;
  if found then return case when v_existing = 'accepted' then 'accepted' else 'blocked' end; end if;
  if exists (select 1 from public.kwtsms_deliveries where phone_hash = p_phone
      and created_at > v_now - interval '3 minutes')
    or (select count(*) from public.kwtsms_deliveries where phone_hash = p_phone
      and created_at > v_now - interval '1 hour') >= 5
    or (select count(*) from public.kwtsms_deliveries
      where created_at > v_now - interval '1 second') >= 5
    or (select count(*) from public.kwtsms_deliveries
      where created_at > v_now - interval '1 hour') >= 100 then
    return 'blocked';
  end if;
  insert into public.kwtsms_deliveries(event_hash,phone_hash,test_mode,created_at)
    values (p_event,p_phone,p_test,v_now);
  return 'send';
end;
$$;
create function public.finish_kwtsms_send(p_event text,p_outcome text,p_msgid text,
  p_charged numeric,p_balance numeric) returns void
language sql security definer set search_path = '' as $$
  update public.kwtsms_deliveries set outcome=p_outcome,provider_msgid=p_msgid,
    points_charged=p_charged,balance_after=p_balance
  where event_hash=p_event and outcome='pending';
$$;
revoke all on function public.reserve_kwtsms_send(text,text,boolean) from public,anon,authenticated;
revoke all on function public.finish_kwtsms_send(text,text,text,numeric,numeric) from public,anon,authenticated;
grant execute on function public.reserve_kwtsms_send(text,text,boolean) to service_role;
grant execute on function public.finish_kwtsms_send(text,text,text,numeric,numeric) to service_role;
commit;
