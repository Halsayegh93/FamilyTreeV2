-- رسائل الدخول · «محاولات الدخول» (طلب المالك ٢٠٢٦-١٠-٢٠: «منو حاول يدخل وكم مرة؟ برقم هاتفه؟»؛
-- الرؤية: «المالك كامل، المدير مخفي»). مُعدّ ولم يُطبَّق — ينتظر «نعم» المالك.
--  ١) login_attempts: سطر لكل طلب رمز وصل الدالة الطرفية send-sms-kwtsms — الرقم كما هو (965XXXXXXXX) والنتيجة فقط
--     (sent / failed / unknown / blocked / test)، بلا الرمز ولا بصمات kwtsms_deliveries (فلا ربط بين الجدولين).
--     مقفول تماماً (RLS بلا سياسات + سحب كل الصلاحيات من التطبيقات، والتسلسل كذلك). يُحفظ ٣٠ يوماً ثم يُحذف تلقائياً.
--     profile_id تلميح وقت الإدراج بلا مفتاح أجنبي — حذف/دمج/نقل الملفات (adopt = نسخ + حذف) لا يلمس هذا الجدول
--     ولا ينتظره؛ القراءة تعيد المطابقة بالرقم وتتجاهل المعرّف لو انحذف صاحبه.
--  ٢) log_login_attempt(p_phone, p_outcome) — للدالة الطرفية فقط (service_role). تتحقق، تطابق العضو بالرقم، تُدرج،
--     وتحذف حتى ٢٠٠ سطر أقدم من ٣٠ يوماً في كل استدعاء (رخيص ومحدود).
--  ٣) sms_login_attempts(p_days) — للمالك والمدير فقط (غيرهما 42501): الأرقام مجمّعة (الأحدث أولاً، أقصى ٢٠٠)
--     مع العدد اليوم/في الفترة والنتائج وأول/آخر محاولة وهل دخل بعدها و«مريب» (٥ محاولات أو أكثر في ساعة واحدة).
--     المالك يرى الرقم كاملاً، المدير مخفياً: «+965 9003••65» (أول ٤ وآخر خانتين). auth.users تُقرأ داخل دالة
--     SECURITY DEFINER فقط (لا صلاحية للتطبيقات عليها).
-- ملاحظة: حد Supabase نفسه (٦٠ ثانية لكل رقم) يرد قبل الدالة الطرفية، فتلك الطلبات لا تصل ولا تُعدّ.
-- التراجع: supabase/rollback/20261020160000_login_attempts_rollback.sql
-- تجربة محلية: cd supabase/tests/family_links && node login_attempts.test.mjs

-- ١) الجدول
create table public.login_attempts (
  id          bigserial primary key,
  phone       text not null check (phone ~ '^965[4569][0-9]{7}$'),
  profile_id  uuid,                 -- تلميح وقت الإدراج (بلا مفتاح أجنبي عمداً)
  outcome     text not null check (outcome in ('sent', 'failed', 'unknown', 'blocked', 'test')),
  created_at  timestamptz not null default now()
);
create index login_attempts_phone_time on public.login_attempts (phone, created_at);
create index login_attempts_created_time on public.login_attempts (created_at);
alter table public.login_attempts enable row level security;
revoke all on public.login_attempts from public, anon, authenticated;
revoke all on sequence public.login_attempts_id_seq from public, anon, authenticated;

-- مطابقة العضو بالرقم (داخلية — تُستدعى من الدالتين أدناه فقط، لا تنفيذ للتطبيقات).
-- الرقم في الملف «+965XXXXXXXX» (فهرس فريد)، والصيغ القديمة احتياطاً؛ وإن لم يوجد فحساب الدخول بنفس الرقم
-- (معرّف الملف من app_metadata.profile_id كما في current_profile_id، وإلا معرّف الحساب).
create function public.login_attempt_profile_id(p_phone text) returns uuid
language sql stable set search_path = '' as $$
  select coalesce(
    (select p.id from public.profiles p
      where p.phone_number in ('+' || p_phone, p_phone, '00' || p_phone, substr(p_phone, 4))
      order by (p.status = 'active') desc, p.created_at nulls last, p.id
      limit 1),
    (select p.id from auth.users u
       join public.profiles p on p.id = coalesce(
         case when u.raw_app_meta_data ->> 'profile_id'
                   ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              then (u.raw_app_meta_data ->> 'profile_id')::uuid end,
         u.id)
      where u.phone = p_phone
      order by u.last_sign_in_at desc nulls last, p.id
      limit 1));
$$;
revoke all on function public.login_attempt_profile_id(text) from public, anon, authenticated;

-- ٢) التسجيل (الدالة الطرفية فقط)
create function public.log_login_attempt(p_phone text, p_outcome text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if p_phone is null or p_phone !~ '^965[4569][0-9]{7}$'
     or p_outcome is null or p_outcome not in ('sent', 'failed', 'unknown', 'blocked', 'test') then
    raise exception 'Invalid login attempt' using errcode = '22023';
  end if;
  insert into public.login_attempts (phone, profile_id, outcome)
  values (p_phone, public.login_attempt_profile_id(p_phone), p_outcome);
  -- الحفظ ٣٠ يوماً: حذف محدود في كل استدعاء (يلحق دائماً — كل إدراج يحذف حتى ٢٠٠)
  delete from public.login_attempts
   where id in (select a.id from public.login_attempts a
                 where a.created_at < now() - interval '30 days'
                 order by a.created_at limit 200);
end;
$$;
revoke all on function public.log_login_attempt(text, text) from public, anon, authenticated;
grant execute on function public.log_login_attempt(text, text) to service_role;

-- ٣) القراءة (المالك كامل، المدير مخفي)
create function public.sms_login_attempts(p_days int default 7) returns jsonb
language plpgsql security definer set search_path = '' stable as $$
declare
  v_role   text := public.current_user_role();
  v_full   boolean;
  v_days   int := least(greatest(coalesce(p_days, 7), 1), 30);
  v_today  date := (now() at time zone 'Asia/Kuwait')::date;
  v_from   timestamptz;
  v_midnight timestamptz;
  v_items  jsonb;
  v_totals jsonb;
begin
  if coalesce(v_role, '') not in ('owner', 'admin') then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;
  v_full := v_role = 'owner';
  -- الفترة بأيام الكويت: اليوم + (الأيام - ١) قبله
  v_midnight := v_today::timestamp at time zone 'Asia/Kuwait';
  v_from := (v_today - (v_days - 1))::timestamp at time zone 'Asia/Kuwait';

  with g as (
    select a.phone,
           count(*)                                              as attempts,
           count(*) filter (where a.created_at >= v_midnight)    as today,
           count(*) filter (where a.outcome = 'sent')            as sent,
           count(*) filter (where a.outcome = 'blocked')         as blocked,
           count(*) filter (where a.outcome = 'failed')          as failed,
           count(*) filter (where a.outcome = 'unknown')         as unknown,
           count(*) filter (where a.outcome = 'test')            as test,
           min(a.created_at)                                     as first_at,
           max(a.created_at)                                     as last_at,
           (array_agg(a.outcome order by a.created_at desc, a.id desc))[1] as last_outcome,
           (array_agg(a.profile_id order by a.created_at desc, a.id desc)
              filter (where a.profile_id is not null))[1]       as stored_profile
      from public.login_attempts a
     where a.created_at >= v_from
     group by a.phone
  ), h as (
    select x.phone, max(x.n) as max_in_hour
      from (select a.phone, count(*) as n
              from public.login_attempts a
             where a.created_at >= v_from
             group by a.phone, date_trunc('hour', a.created_at)) x
     group by x.phone
  ), r as (
    select g.*, h.max_in_hour, p.id as profile_id, p.full_name, p.first_name, p.status as member_status,
           (select max(u.last_sign_in_at) from auth.users u where u.phone = g.phone) as last_sign_in_at
      from g
      join h on h.phone = g.phone
      left join lateral (
        select pp.id, pp.full_name, pp.first_name, pp.status
          from public.profiles pp
         where pp.id = coalesce(public.login_attempt_profile_id(g.phone), g.stored_profile)
      ) p on true
  )
  select
    jsonb_build_object(
      'phones', count(*),
      'attempts', coalesce(sum(r.attempts), 0),
      'unknown_numbers', count(*) filter (where r.profile_id is null),
      'suspicious', count(*) filter (where r.max_in_hour >= 5)),
    coalesce((select jsonb_agg(j order by t.last_at desc, t.phone)
                from (select r2.last_at, r2.phone, jsonb_build_object(
                        'phone', '+965 ' || case when v_full then substr(r2.phone, 4)
                                                 else substr(r2.phone, 4, 4) || '••' || right(r2.phone, 2) end,
                        'phone_e164', case when v_full then '+' || r2.phone end,
                        'profile_id', r2.profile_id,
                        'name', coalesce(nullif(btrim(r2.full_name), ''), nullif(btrim(r2.first_name), '')),
                        'is_member', r2.profile_id is not null,
                        'member_status', r2.member_status,
                        'attempts_today', r2.today,
                        'attempts_in_window', r2.attempts,
                        'sent', r2.sent,
                        'blocked', r2.blocked,
                        'failed', r2.failed,
                        'unknown', r2.unknown,
                        'test', r2.test,
                        'first_at', r2.first_at,
                        'last_at', r2.last_at,
                        'last_outcome', r2.last_outcome,
                        'logged_in', coalesce(r2.last_sign_in_at >= r2.first_at, false),
                        'last_sign_in_at', r2.last_sign_in_at,
                        'max_in_hour', r2.max_in_hour,
                        'suspicious', r2.max_in_hour >= 5) j
                        from r r2
                       order by r2.last_at desc, r2.phone
                       limit 200) t), '[]'::jsonb)
    into v_totals, v_items
    from r;

  return jsonb_build_object(
    'days', v_days,
    'masked', not v_full,
    'retention_days', 30,
    'generated_at', now(),
    'totals', v_totals,
    'items', v_items);
end;
$$;
revoke all on function public.sms_login_attempts(int) from public, anon;
grant execute on function public.sms_login_attempts(int) to authenticated;
