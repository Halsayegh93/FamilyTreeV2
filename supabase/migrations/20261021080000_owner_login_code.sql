-- رسائل الدخول · «اعرض الرمز» للمالك وحده (طلب المالك ٢٠٢٦-١٠-٢١: «لازم اشوف رمز الدخول علشان اذا في خطا
-- ممكن اعطيه لصاحب الرقم» — اختار «لي أنا بس»). الرمز يتأخر/ما يوصل ← المالك يقرأه للعضو اللي تواصل معه.
--
--  ١) private.login_codes — آخر رمز أُرسل لكل رقم فقط (رمز جديد يحلّ محل القديم، كما يبطله Supabase). تحفظه الدالة
--     الطرفية send-sms-kwtsms بعد قبول KWT للرسالة فقط (فشل/انقطاع ← Supabase ما يحفظ الرمز أصلاً، والوضع التجريبي
--     لا يُحفظ). مخطط private: لا تصله التطبيقات ولا PostgREST (usage للمالك postgres فقط على الحي).
--     الصلاحية ٣٠٠ ثانية = sms_otp_exp في إعدادات Auth على الحي (٢٠٢٦-١٠-٢٠). يُمسح نهائياً: عند الرمز التالي،
--     وبمهمة «login-codes-cleanup» كل ٥ دقائق (المنتهي، أو من دخل بعده — الرمز استُعمل فبطل).
--  ٢) private.login_code_views — سجل كل «اعرض الرمز» (الرقم، من، متى، النتيجة) — بلا الرمز. يُحفظ بمدة سجل
--     «محاولات الدخول» (login_attempts_retention_days، افتراضياً ٣٠ يوماً).
--  ٣) store_login_code(p_phone, p_code) — للدالة الطرفية فقط (service_role).
--  ٤) owner_login_codes(p_days) — للمالك فقط (غيره 42501، حتى المدير): الأرقام التي لها رمز صالح الآن (بلا الرمز
--     نفسه) + آخر «عرض» لكل رقم خلال الفترة — تعرض صفحة «محاولات الدخول» منه زر «اعرض الرمز» وسطر «عرضت الرمز».
--  ٥) owner_reveal_login_code(p_phone) — للمالك فقط: يُسجَّل في login_code_views دائماً ثم يرجع
--     shown (الرمز + وقت انتهائه) · used (دخل بعده — بطل) · expired · none.
--  لا يتغيّر شيء قائم: log_login_attempt وsms_login_attempts وبقية دوال KWT كما هي حرفياً.
--
-- التراجع: supabase/rollback/20261021080000_owner_login_code_rollback.sql
-- تجربة محلية: cd supabase/tests/family_links && node owner_login_code.test.mjs

-- ═══ ١ و٢) الجدولان ═══
create table private.login_codes (
  phone      text primary key check (phone ~ '^965[4569][0-9]{7}$'),
  code       text not null check (code ~ '^[0-9]{6}$'),
  sent_at    timestamptz not null default now(),
  expires_at timestamptz not null
);
create table private.login_code_views (
  id         bigserial primary key,
  phone      text not null check (phone ~ '^965[4569][0-9]{7}$'),
  viewed_by  uuid,
  viewed_at  timestamptz not null default now(),
  result     text not null check (result in ('shown', 'used', 'expired', 'none'))
);
create index login_code_views_phone_time on private.login_code_views (phone, viewed_at);
alter table private.login_codes enable row level security;
alter table private.login_code_views enable row level security;
revoke all on private.login_codes, private.login_code_views from public, anon, authenticated, service_role;
revoke all on sequence private.login_code_views_id_seq from public, anon, authenticated, service_role;

-- الرمز صالح: لم ينتهِ، وصاحب الرقم لم يدخل بعد إرساله (الدخول يبطله). auth.users داخل دوال SECURITY DEFINER فقط.
create function private.login_code_valid(p_phone text, p_sent_at timestamptz, p_expires_at timestamptz) returns boolean
language sql stable set search_path = '' as $$
  select p_expires_at > now()
     and not exists (select 1 from auth.users u where u.phone = p_phone and u.last_sign_in_at > p_sent_at);
$$;
revoke all on function private.login_code_valid(text, timestamptz, timestamptz) from public, anon, authenticated, service_role;

-- ═══ ٣) الحفظ (الدالة الطرفية فقط) ═══
create function public.store_login_code(p_phone text, p_code text) returns void
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

-- ═══ ٤) الأرقام التي لها رمز صالح + آخر عرض (المالك فقط) ═══
create function public.owner_login_codes(p_days int default 7) returns jsonb
language plpgsql security definer set search_path = '' stable as $$
declare
  v_days  int := least(greatest(coalesce(p_days, 7), 1), 90);
  v_from  timestamptz;
begin
  if coalesce(public.current_user_role(), '') <> 'owner' then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;
  -- نفس الفترة بأيام الكويت كما في sms_login_attempts
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
$$;
revoke all on function public.owner_login_codes(int) from public, anon;
grant execute on function public.owner_login_codes(int) to authenticated;

-- ═══ ٥) «اعرض الرمز» (المالك فقط) — كل نداء يُسجَّل ═══
create function public.owner_reveal_login_code(p_phone text) returns jsonb
language plpgsql security definer set search_path = '' as $$
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
$$;
revoke all on function public.owner_reveal_login_code(text) from public, anon;
grant execute on function public.owner_reveal_login_code(text) to authenticated;

-- ═══ التنظيف: كل ٥ دقائق يمسح المنتهي والمستعمل (مهمة pg_cron فقط — لا تنفيذ للتطبيقات ولا للخدمة) ═══
create function public.cleanup_login_codes() returns int
language plpgsql security definer set search_path = '' as $$
declare v_n int;
begin
  delete from private.login_codes c where not private.login_code_valid(c.phone, c.sent_at, c.expires_at);
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
revoke all on function public.cleanup_login_codes() from public, anon, authenticated, service_role;

select cron.schedule('login-codes-cleanup', '*/5 * * * *', 'select public.cleanup_login_codes()');
