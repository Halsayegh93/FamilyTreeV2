-- رسائل الدخول · رمز كل رسالة في «تفاصيل الرقم» + مسح رسائل الرقم مع «فك القفل» (طلب المالك ٢٠٢٦-١٠-٢٣:
-- «ابى طول الوقت حتى اذا انته منه» · «حط بالخانة ان الرمز صالح او منتهي وحطه بداخل ملف العرض عند كل رسالة» ·
-- «مع التصفير احذف الرسائل القديمة»).
--
--  ١) private.login_code_history — كل رمز أُرسل (لا آخر رمز فقط)، يُحفظ بمدة سجل «محاولات الدخول»
--     (login_attempts_retention_days، افتراضياً ٣٠ يوماً). private.login_codes (آخر رمز صالح) كما هو.
--  ٢) store_login_code — التوقيع نفسه (تناديه الدالة الطرفية send-sms-kwtsms، لا تُمس): يضيف للسجل ويمسح الأقدم من المدة.
--  ٣) owner_number_login_codes(p_phone, p_days) — للمالك فقط (غيره 42501): رموز الرقم في الفترة، لكل رمز
--     valid (آخر رمز للرقم، لم ينتهِ، ولم يدخل صاحبه بعده) أو expired. كل نداء يُسجَّل في login_code_views (shown).
--  ٤) owner_clear_number_messages(p_phone) — للمالك فقط: يمسح طلبات الرقم من login_attempts ورموزه (السجل والصالح).
--     سجل «عرضت الرمز» (login_code_views) يبقى. التطبيق يناديه بعد نجاح «فك القفل» (kwtsms-admin لا يُمس).
--  ٥) التنظيف كل ٥ دقائق: cleanup_login_codes يمسح أيضاً من السجل ما تجاوز المدة.
--
-- التراجع: supabase/rollback/20261023180000_login_code_history_rollback.sql

create table private.login_code_history (
  id         bigserial primary key,
  phone      text not null check (phone ~ '^965[4569][0-9]{7}$'),
  code       text not null check (code ~ '^[0-9]{6}$'),
  sent_at    timestamptz not null default now(),
  expires_at timestamptz not null
);
create index login_code_history_phone_time on private.login_code_history (phone, sent_at);
alter table private.login_code_history enable row level security;
revoke all on private.login_code_history from public, anon, authenticated, service_role;
revoke all on sequence private.login_code_history_id_seq from public, anon, authenticated, service_role;

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
$$;
revoke all on function public.store_login_code(text, text) from public, anon, authenticated;
grant execute on function public.store_login_code(text, text) to service_role;

create function public.owner_number_login_codes(p_phone text, p_days int default 7) returns jsonb
language plpgsql security definer set search_path = '' as $$
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
$$;
revoke all on function public.owner_number_login_codes(text, int) from public, anon;
grant execute on function public.owner_number_login_codes(text, int) to authenticated;

create function public.owner_clear_number_messages(p_phone text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_phone text := regexp_replace(coalesce(p_phone, ''), '^(\+|00)', '');
  v_attempts int; v_codes int;
begin
  if coalesce(public.current_user_role(), '') <> 'owner' then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;
  if v_phone !~ '^965[4569][0-9]{7}$' then
    raise exception 'Invalid phone' using errcode = '22023';
  end if;
  delete from public.login_attempts where phone = v_phone;
  get diagnostics v_attempts = row_count;
  delete from private.login_code_history where phone = v_phone;
  get diagnostics v_codes = row_count;
  delete from private.login_codes where phone = v_phone;
  return jsonb_build_object('ok', true, 'cleared_attempts', v_attempts, 'cleared_codes', v_codes);
end;
$$;
revoke all on function public.owner_clear_number_messages(text) from public, anon;
grant execute on function public.owner_clear_number_messages(text) to authenticated;

create or replace function public.cleanup_login_codes() returns int
language plpgsql security definer set search_path = '' as $$
declare v_n int; v_keep int;
begin
  delete from private.login_codes c where not private.login_code_valid(c.phone, c.sent_at, c.expires_at);
  get diagnostics v_n = row_count;
  select a.login_attempts_retention_days into v_keep
    from public.app_settings a order by a.updated_at desc limit 1;
  delete from private.login_code_history h where h.sent_at < now() - make_interval(days => coalesce(v_keep, 30));
  return v_n;
end;
$$;
revoke all on function public.cleanup_login_codes() from public, anon, authenticated, service_role;
