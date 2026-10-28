-- تراجع 20261029110000_remove_owner_code_view (الدوال بنصّها السابق حرفياً). الرموز الممسوحة لا تعود.
-- ملاحظة: الخطّاف send-sms-kwtsms v26 لا ينادي store_login_code — للحفظ من جديد أعد نشر v25 (verify_jwt=false دائماً).
CREATE OR REPLACE FUNCTION public.store_login_code(p_phone text, p_code text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_keep int;
begin
  if p_phone is null or p_phone !~ '^965[4569][0-9]{7}$' or p_code is null or p_code !~ '^[0-9]{6}$' then
    raise exception 'Invalid login code' using errcode = '22023';
  end if;
  insert into private.login_codes (phone, code, sent_at, expires_at)
  values (p_phone, p_code, now(), now() + interval '300 seconds')
  on conflict (phone) do update
    set code = excluded.code, sent_at = excluded.sent_at, expires_at = excluded.expires_at;
  insert into private.login_code_history (phone, code, sent_at, expires_at)
  values (p_phone, p_code, now(), now() + interval '300 seconds');
  delete from private.login_codes where expires_at <= now();
  select a.login_attempts_retention_days into v_keep
    from public.app_settings a order by a.updated_at desc limit 1;
  delete from private.login_code_views
   where id in (select v.id from private.login_code_views v
                 where v.viewed_at < now() - make_interval(days => coalesce(v_keep, 30))
                 order by v.viewed_at limit 200);
  delete from private.login_code_history
   where id in (select h.id from private.login_code_history h
                 where h.sent_at < now() - make_interval(days => coalesce(v_keep, 30))
                 order by h.sent_at limit 200);
end;
$function$;

CREATE OR REPLACE FUNCTION public.owner_login_codes(p_days integer DEFAULT 7)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_days  int := least(greatest(coalesce(p_days, 7), 1), 90);
  v_from  timestamptz;
begin
  if coalesce(public.current_user_role(), '') <> 'owner' then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;
  v_from := (((now() at time zone 'Asia/Kuwait')::date) - (v_days - 1))::timestamp at time zone 'Asia/Kuwait';
  return jsonb_build_object(
    'codes', coalesce((
      select jsonb_agg(jsonb_build_object('phone_e164', '+' || c.phone, 'sent_at', c.sent_at, 'expires_at', c.expires_at)
                       order by c.sent_at desc)
        from private.login_codes c
       where private.login_code_valid(c.phone, c.sent_at, c.expires_at)), '[]'::jsonb),
    'views', coalesce((
      select jsonb_agg(jsonb_build_object('phone_e164', '+' || v.phone, 'last_viewed_at', v.last_at, 'count', v.n)
                       order by v.last_at desc)
        from (select x.phone, max(x.viewed_at) as last_at, count(*) as n
                from private.login_code_views x
               where x.viewed_at >= v_from
               group by x.phone) v), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION public.owner_reveal_login_code(p_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_phone  text := regexp_replace(coalesce(p_phone, ''), '^(\+|00)', '');
  v_code   text;
  v_sent   timestamptz;
  v_exp    timestamptz;
  v_result text;
begin
  if coalesce(public.current_user_role(), '') <> 'owner' then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;
  if v_phone !~ '^965[4569][0-9]{7}$' then
    raise exception 'Invalid phone' using errcode = '22023';
  end if;
  select c.code, c.sent_at, c.expires_at into v_code, v_sent, v_exp
    from private.login_codes c where c.phone = v_phone;
  v_result := case
    when v_code is null then 'none'
    when v_exp <= now() then 'expired'
    when not private.login_code_valid(v_phone, v_sent, v_exp) then 'used'
    else 'shown' end;
  insert into private.login_code_views (phone, viewed_by, result)
  values (v_phone, public.current_profile_id(), v_result);
  return jsonb_build_object(
    'status', v_result,
    'code', case when v_result = 'shown' then v_code end,
    'sent_at', v_sent,
    'expires_at', case when v_result = 'shown' then v_exp end);
end;
$function$;

CREATE OR REPLACE FUNCTION public.owner_number_login_codes(p_phone text, p_days integer DEFAULT 7)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_phone text := regexp_replace(coalesce(p_phone, ''), '^(\+|00)', '');
  v_keep int; v_days int; v_from timestamptz; v_last_id bigint; v_codes jsonb;
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
  select h.id into v_last_id from private.login_code_history h
   where h.phone = v_phone order by h.sent_at desc, h.id desc limit 1;
  select coalesce(jsonb_agg(jsonb_build_object('code', h.code, 'sent_at', h.sent_at, 'expires_at', h.expires_at,
           'status', case when h.id = v_last_id and private.login_code_valid(h.phone, h.sent_at, h.expires_at)
                          then 'valid' else 'expired' end)
         order by h.sent_at desc, h.id desc), '[]'::jsonb)
    into v_codes from private.login_code_history h where h.phone = v_phone and h.sent_at >= v_from;
  if jsonb_array_length(v_codes) > 0 then
    insert into private.login_code_views (phone, viewed_by, result)
    values (v_phone, public.current_profile_id(), 'shown');
  end if;
  return jsonb_build_object('phone_e164', '+' || v_phone, 'codes', v_codes);
end;
$function$;

revoke all on function public.owner_login_codes(integer) from public, anon;
revoke all on function public.owner_reveal_login_code(text) from public, anon;
revoke all on function public.owner_number_login_codes(text, integer) from public, anon;
grant execute on function public.owner_login_codes(integer) to authenticated, service_role;
grant execute on function public.owner_reveal_login_code(text) to authenticated, service_role;
grant execute on function public.owner_number_login_codes(text, integer) to authenticated, service_role;
