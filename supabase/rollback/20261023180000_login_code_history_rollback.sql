-- تراجع 20261023180000_login_code_history: store_login_code وcleanup_login_codes كما في 20261021080000،
-- وحذف الدالتين الجديدتين وسجل الرموز.

drop function if exists public.owner_number_login_codes(text, int);
drop function if exists public.owner_clear_number_messages(text);

create or replace function public.store_login_code(p_phone text, p_code text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_keep int;
begin
  if p_phone is null or p_phone !~ '^965[4569][0-9]{7}$' or p_code is null or p_code !~ '^[0-9]{6}$' then
    raise exception 'Invalid login code' using errcode = '22023';
  end if;
  insert into private.login_codes (phone, code, sent_at, expires_at)
  values (p_phone, p_code, now(), now() + interval '300 seconds')
  on conflict (phone) do update
    set code = excluded.code, sent_at = excluded.sent_at, expires_at = excluded.expires_at;
  delete from private.login_codes where expires_at <= now();
  select a.login_attempts_retention_days into v_keep
    from public.app_settings a order by a.updated_at desc limit 1;
  delete from private.login_code_views
   where id in (select v.id from private.login_code_views v
                 where v.viewed_at < now() - make_interval(days => coalesce(v_keep, 30))
                 order by v.viewed_at limit 200);
end;
$$;
revoke all on function public.store_login_code(text, text) from public, anon, authenticated;
grant execute on function public.store_login_code(text, text) to service_role;

create or replace function public.cleanup_login_codes() returns int
language plpgsql security definer set search_path = '' as $$
declare v_n int;
begin
  delete from private.login_codes c where not private.login_code_valid(c.phone, c.sent_at, c.expires_at);
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
revoke all on function public.cleanup_login_codes() from public, anon, authenticated, service_role;

drop table if exists private.login_code_history;
