-- Live-safe: all synthetic rows and time adjustments roll back. No provider calls.
begin;
do $$
declare e text := repeat('a',64); p text := repeat('b',64); i integer;
begin
  if public.reserve_kwtsms_send(e,p,true) <> 'send' then raise exception 'first reservation failed'; end if;
  if public.reserve_kwtsms_send(e,p,true) <> 'blocked' then raise exception 'pending replay allowed'; end if;
  perform public.finish_kwtsms_send(e,'accepted','synthetic-test-id',1,99);
  if public.reserve_kwtsms_send(e,p,true) <> 'accepted' then raise exception 'accepted replay failed'; end if;
  if public.reserve_kwtsms_send(repeat('c',64),p,true) <> 'blocked' then raise exception 'cooldown failed'; end if;
  update public.kwtsms_deliveries set created_at = clock_timestamp() - interval '4 minutes' where event_hash=e;
  if public.reserve_kwtsms_send(repeat('c',64),p,true) <> 'send' then raise exception 'cooldown recovery failed'; end if;
  -- Five hourly attempts, all older than cooldown: the sixth must still be blocked.
  for i in 1..3 loop
    insert into public.kwtsms_deliveries(event_hash,phone_hash,test_mode,created_at)
    values (md5('synthetic-event-'||i)||md5('synthetic-event-'||i),p,true,clock_timestamp()-interval '10 minutes');
  end loop;
  update public.kwtsms_deliveries set created_at=clock_timestamp()-interval '4 minutes'
    where event_hash=repeat('c',64);
  if public.reserve_kwtsms_send(repeat('d',64),p,true) <> 'blocked' then raise exception 'hourly limit failed'; end if;
  if has_function_privilege('anon','public.reserve_kwtsms_send(text,text,boolean)','execute')
    or has_function_privilege('authenticated','public.reserve_kwtsms_send(text,text,boolean)','execute')
    or has_table_privilege('anon','public.kwtsms_deliveries','select') then
    raise exception 'client privilege leak';
  end if;
end;
$$;
rollback;
