// تجربة 20261025100000_owner_only_system_areas و20261025100100_insights_owner_admin_only على قاعدة محلية معزولة — لا تلمس
// السيرفر. أربع دوال منسوخة حرفياً من الحي (sms_balance_status، app_config، kwtsms_balance_check، log_login_attempt —
// نصّها هنا يطابق md5 الحي)، والباقي بدائل تحمل سطر الشرط الحي نفسه (الترحيل يستبدل ذلك السطر وحده).
// التشغيل: cd supabase/tests/family_links && node owner_only_system_areas.test.mjs
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
process.on('unhandledRejection', e => { console.log('خطأ:', e.message, (e.query ?? '').slice(0, 300)); process.exit(2); });

const REPO = fileURLToPath(new URL('../../', import.meta.url));
const read = f => readFileSync(`${REPO}/${f}`, 'utf8');
const MIG = read('migrations/20261025100000_owner_only_system_areas.sql');
const RB = read('rollback/20261025100000_owner_only_system_areas_rollback.sql');
const MIG2 = read('migrations/20261025100100_insights_owner_admin_only.sql');
const RB2 = read('rollback/20261025100100_insights_owner_admin_only_rollback.sql');

const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const O = id(1), A = id(2), MON = id(3), S = id(4), M = id(5), FA = id(6);
let pass = 0, fail = 0;
const ok = (c, m, x = '') => { if (c) { pass++; console.log('✓', m); } else { fail++; console.log('✗', m, x); } };

const db = new PGlite();
await db.exec(`
do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role; end if;
end $$;
create schema auth;
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create table public.profiles (id uuid primary key, role text, status text, full_name text, first_name text, phone_number text);
create function public.current_profile_id() returns uuid language sql stable as $$ select auth.uid() $$;
create function public.current_user_role() returns text language sql stable security definer set search_path to 'public' as $$
  select case when p.status = 'active' then p.role when p.status in ('frozen','deleted') then p.status else 'pending' end
  from public.profiles p where p.id = public.current_profile_id() $$;
create table public.app_settings (id int primary key default 1, sms_low_threshold int, sms_urgent_threshold int,
  sms_low_repeat_hours int, sms_urgent_repeat_hours int, sms_wait_seconds int default 60,
  allow_new_registrations boolean default true, login_attempts_retention_days int default 30,
  updated_at timestamptz default now());
insert into public.app_settings (id) values (1);
create table public.notifications (id uuid primary key default gen_random_uuid(), target_member_id uuid, title text, body text,
  kind text, created_by uuid, is_read boolean default false, created_at timestamptz default now());
create table public.kwtsms_deliveries (id bigserial primary key, outcome text, balance_after numeric, test_mode boolean default false,
  created_at timestamptz default now());
create table public.login_attempts (id bigserial primary key, phone text, profile_id uuid, outcome text,
  created_at timestamptz default now(), alerted boolean default false);
create table public.app_config (key text primary key, value jsonb not null, default_value jsonb not null, kind text not null,
  min_value numeric, max_value numeric, max_length int, category text not null, label_ar text not null, help_ar text,
  rules jsonb not null default '{}'::jsonb, is_public boolean not null default false, sort int not null default 0,
  updated_at timestamptz not null default now(), updated_by uuid);
insert into public.app_config (key, value, default_value, kind, category, label_ar, is_public) values
  ('sms_suspicious_per_hour', '5', '5', 'int', 'sms', 'مريب', false),
  ('site_url', '"https://almohali.com"', '"https://almohali.com"', 'text', 'links', 'الموقع', true);
create table public.app_config_history (id bigserial primary key, key text);
create table public.device_tokens (id bigserial primary key, member_id uuid, token text);
create table public.device_revocations (id bigserial primary key, member_id uuid, device_id text);
create table public.banned_phones (id bigserial primary key, phone_number text);
create table public.family_names (id bigserial primary key, name text);
-- ما تستدعيه الدوال المنسوخة
create function public.record_kwtsms_balance(p_balance numeric) returns void language sql as $$ select $$;
create function public.config_int(p_key text, p_fallback integer) returns integer language sql stable as $$
  select coalesce((select (c.value #>> '{}')::int from public.app_config c where c.key = p_key), p_fallback) $$;
create function public.login_attempt_profile_id(p_phone text) returns uuid language sql stable as $$
  select p.id from public.profiles p where p.phone_number = '+' || p_phone limit 1 $$;
`);

// ═══ الدوال الحية حرفياً (pg_get_functiondef ٢٠٢٦-١٠-٢٥) ═══
await db.exec(`CREATE OR REPLACE FUNCTION public.sms_balance_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_low int;
begin
  if coalesce(public.current_user_role(), '') not in ('owner', 'admin') then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;
  select balance_after, created_at into r from public.kwtsms_deliveries
   where outcome = 'accepted' and balance_after is not null and not test_mode
   order by created_at desc limit 1;
  select a.sms_low_threshold into v_low from public.app_settings a order by a.updated_at desc limit 1;
  return jsonb_build_object('balance', r.balance_after, 'at', r.created_at,
                            'low', coalesce(r.balance_after < coalesce(v_low, 50), false));
end;
$function$
`);
await db.exec(`CREATE OR REPLACE FUNCTION public.app_config()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_role   text := coalesce(public.current_user_role(), '');
  v_member boolean := v_role in ('owner', 'admin', 'monitor', 'supervisor', 'member');
  v_values jsonb;
  v_at     timestamptz;
  v_wait   integer;
  v_open   boolean;
  v_set_at timestamptz;
  v_out    jsonb;
begin
  select coalesce(jsonb_object_agg(c.key, c.value), '{}'::jsonb), max(c.updated_at)
    into v_values, v_at
    from public.app_config c
   where v_member or c.is_public;
  select a.sms_wait_seconds, a.allow_new_registrations, a.updated_at
    into v_wait, v_open, v_set_at
    from public.app_settings a order by a.updated_at desc limit 1;
  v_out := jsonb_build_object(
    'values', v_values || jsonb_build_object('sms_wait_seconds', coalesce(v_wait, 60),
                                             'allow_new_registrations', coalesce(v_open, true)),
    'scope', case when v_member then 'member' else 'public' end,
    'updated_at', greatest(v_at, v_set_at));
  if v_role in ('owner', 'admin') then
    v_out := v_out || jsonb_build_object(
      'can_edit', v_role = 'owner',
      'categories', jsonb_build_array(
        jsonb_build_object('key', 'members', 'label_ar', 'الأعضاء', 'sort', 10),
        jsonb_build_object('key', 'news', 'label_ar', 'الأخبار', 'sort', 20),
        jsonb_build_object('key', 'tree', 'label_ar', 'الشجرة', 'sort', 30),
        jsonb_build_object('key', 'notifications', 'label_ar', 'الإشعارات والإعلانات', 'sort', 40),
        jsonb_build_object('key', 'approvals', 'label_ar', 'الموافقات', 'sort', 50),
        jsonb_build_object('key', 'deaths', 'label_ar', 'الوفيات', 'sort', 60),
        jsonb_build_object('key', 'sms', 'label_ar', 'رسائل الدخول', 'sort', 70),
        jsonb_build_object('key', 'links', 'label_ar', 'الروابط', 'sort', 80),
        jsonb_build_object('key', 'general', 'label_ar', 'عام', 'sort', 90)),
      'meta', (select coalesce(jsonb_object_agg(c.key, jsonb_build_object(
                 'kind', c.kind, 'label_ar', c.label_ar, 'help_ar', c.help_ar, 'category', c.category,
                 'sort', c.sort, 'min', c.min_value, 'max', c.max_value, 'max_length', c.max_length,
                 'rules', c.rules, 'is_public', c.is_public, 'default', c.default_value,
                 'is_default', c.value = c.default_value, 'updated_at', c.updated_at, 'updated_by', c.updated_by,
                 'updated_by_name', coalesce(nullif(btrim(p.full_name), ''), nullif(btrim(p.first_name), '')))), '{}'::jsonb)
                 from public.app_config c
                 left join public.profiles p on p.id = c.updated_by));
  end if;
  return v_out;
end;
$function$
`);
await db.exec(`CREATE OR REPLACE FUNCTION public.kwtsms_balance_check(p_balance numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_urgent boolean;
  v_title  text;
  v_body   text;
  v_low    int;
  v_crit   int;
  v_low_h  int;
  v_crit_h int;
  v_state  text;
  v_sent   int;
begin
  perform public.record_kwtsms_balance(p_balance);
  select a.sms_low_threshold, a.sms_urgent_threshold, a.sms_low_repeat_hours, a.sms_urgent_repeat_hours
    into v_low, v_crit, v_low_h, v_crit_h
    from public.app_settings a order by a.updated_at desc limit 1;
  v_low := coalesce(v_low, 50);  v_crit := coalesce(v_crit, 10);
  v_low_h := coalesce(v_low_h, 24);  v_crit_h := coalesce(v_crit_h, 12);
  if p_balance >= v_low then
    return jsonb_build_object('recorded', true, 'state', 'ok', 'alerted', false);
  end if;
  v_urgent := p_balance < v_crit;
  v_state := case when v_urgent then 'urgent' else 'low' end;
  if exists (
    select 1 from public.notifications n
     where n.kind = 'sms_balance_low'
       and n.created_at > now() - make_interval(hours => case when v_urgent then v_crit_h else v_low_h end)
       and (not v_urgent or n.title like '%عاجل%')
  ) then
    return jsonb_build_object('recorded', true, 'state', v_state, 'alerted', false);
  end if;
  v_title := case when v_urgent then 'عاجل: رصيد رسائل الدخول قارب يخلص' else 'رصيد رسائل الدخول قليل' end;
  v_body  := 'باقي ' || trim(to_char(p_balance, 'FM999999990')) || ' نقطة في KWT SMS — كل رمز دخول بنقطة. '
             || 'اشحن الرصيد حتى ما يوقف تسجيل الدخول.';
  insert into public.notifications (target_member_id, title, body, kind, created_by, is_read)
  select p.id, v_title, v_body, 'sms_balance_low', null, false
    from public.profiles p
   where p.role in ('owner', 'admin') and p.status = 'active';
  get diagnostics v_sent = row_count;
  return jsonb_build_object('recorded', true, 'state', v_state, 'alerted', v_sent > 0);
end;
$function$
`);
await db.exec(`CREATE OR REPLACE FUNCTION public.log_login_attempt(p_phone text, p_outcome text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_keep    int;
  v_id      bigint;
  v_profile uuid;
  v_n       int;
  v_name    text;
begin
  if p_phone is null or p_phone !~ '^965[4569][0-9]{7}$'
     or p_outcome is null or p_outcome not in ('sent', 'failed', 'unknown', 'blocked', 'test') then
    raise exception 'Invalid login attempt' using errcode = '22023';
  end if;
  v_profile := public.login_attempt_profile_id(p_phone);
  insert into public.login_attempts (phone, profile_id, outcome)
  values (p_phone, v_profile, p_outcome)
  returning id into v_id;
  select a.login_attempts_retention_days into v_keep
    from public.app_settings a order by a.updated_at desc limit 1;
  delete from public.login_attempts
   where id in (select a.id from public.login_attempts a
                 where a.created_at < now() - make_interval(days => coalesce(v_keep, 30))
                 order by a.created_at limit 200);

  -- تنبيه «محاولات دخول مريبة» — بأفضل جهد: أي خطأ هنا يتراجع وحده ولا يصل للدالة الطرفية
  begin
    select count(*) into v_n from public.login_attempts a
     where a.phone = p_phone and a.created_at > now() - interval '60 minutes';
    -- القفل غير منتظِر: محاولة متزامنة لنفس الرقم تتركه لصاحبة القفل
    if v_n >= public.config_int('sms_suspicious_per_hour', 5) and pg_catalog.pg_try_advisory_xact_lock(20261020, pg_catalog.hashtext(p_phone)) then
      -- عبارة منفصلة بعد القفل (لقطة جديدة) ترى تنبيهاً التزم للتو
      if not exists (select 1 from public.login_attempts a
                      where a.phone = p_phone and a.alerted
                        and a.created_at > now() - interval '12 hours') then
        update public.login_attempts set alerted = true where id = v_id;
        select coalesce(nullif(btrim(p.full_name), ''), nullif(btrim(p.first_name), '')) into v_name
          from public.profiles p where p.id = v_profile;
        insert into public.notifications (target_member_id, title, body, kind, created_by, is_read)
        select p.id, 'محاولات دخول مريبة',
               coalesce(v_name, 'رقم غير مسجّل') || ' طلب رمز الدخول ' || v_n || ' مرات خلال ساعة — +965 '
               || case when p.role = 'owner' then substr(p_phone, 4)
                       else substr(p_phone, 4, 4) || '••' || right(p_phone, 2) end,
               'sms_suspicious', null, false
          from public.profiles p
         where p.role in ('owner', 'admin') and p.status = 'active';
      end if;
    end if;
  exception when others then
    raise warning 'log_login_attempt: suspicious alert skipped (%)', sqlstate;
  end;
end;
$function$
`);

// ═══ بدائل بسطر الشرط الحي نفسه (الدوال الحية أطول — الترحيل يستبدل هذا السطر وحده) ═══
await db.exec(`
create function public.sms_admin_overview() returns jsonb language plpgsql stable security definer set search_path to '' as $f$
begin
  if coalesce(public.current_user_role(), '') not in ('owner', 'admin') then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;
  return jsonb_build_object('alerts', jsonb_build_object('low_threshold', 50,
                                 'recipients', 'owner_admins'));
end $f$;
create function public.sms_login_attempts(p_days integer default 7) returns jsonb language plpgsql stable security definer
  set search_path to '' as $f$
declare
  v_role   text := public.current_user_role();
begin
  if coalesce(v_role, '') not in ('owner', 'admin') then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;
  return jsonb_build_object('days', p_days, 'masked', v_role <> 'owner');
end $f$;
create function public.finish_kwtsms_send(p_event text, p_outcome text, p_msgid text, p_charged numeric, p_balance numeric,
  p_error_code text default null) returns void language plpgsql security definer set search_path to '' as $f$
begin
  if p_outcome = 'accepted' and p_balance < 50 then
    insert into public.notifications (target_member_id, title, body, kind, created_by, is_read)
    select p.id, 'رصيد رسائل الدخول قليل', 'باقي ' || p_balance, 'sms_balance_low', null, false
      from public.profiles p
     where p.role in ('owner', 'admin') and p.status = 'active';
  end if;
end $f$;
create function public.approvals_report(p_from timestamptz, p_to timestamptz) returns jsonb language plpgsql stable
  security definer set search_path to '' as $f$
begin
  if coalesce(public.current_user_role(), '') not in ('owner', 'admin', 'monitor') then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;
  return jsonb_build_object('from', p_from, 'to', p_to);
end $f$;
`);

// ═══ السياسات الحية (pg_policies ٢٠٢٦-١٠-٢٥) ═══
await db.exec(`
alter table public.device_tokens enable row level security;
create policy device_tokens_admin_delete on public.device_tokens for delete to public
  using (current_user_role() = any (array['admin'::text, 'owner'::text]));
create policy device_tokens_delete_self on public.device_tokens for delete to public using (member_id = auth.uid());
create policy device_tokens_insert_self on public.device_tokens for insert to authenticated with check (member_id = auth.uid());
create policy device_tokens_select_self_or_admin on public.device_tokens for select to authenticated
  using ((member_id = auth.uid()) or (current_user_role() = any (array['owner'::text, 'admin'::text])));
create policy device_tokens_update_self on public.device_tokens for update to authenticated
  using (member_id = auth.uid()) with check (member_id = auth.uid());
alter table public.device_revocations enable row level security;
create policy device_revocations_delete on public.device_revocations for delete to authenticated
  using ((member_id = auth.uid()) or (current_user_role() = any (array['owner'::text, 'admin'::text])));
create policy device_revocations_insert_admin on public.device_revocations for insert to authenticated
  with check (current_user_role() = any (array['owner'::text, 'admin'::text]));
create policy device_revocations_select on public.device_revocations for select to authenticated
  using ((member_id = auth.uid()) or (current_user_role() = any (array['owner'::text, 'admin'::text])));
create policy device_revocations_update_admin on public.device_revocations for update to authenticated
  using (current_user_role() = any (array['owner'::text, 'admin'::text]))
  with check (current_user_role() = any (array['owner'::text, 'admin'::text]));
alter table public.banned_phones enable row level security;
create policy banned_phones_delete on public.banned_phones for delete to public using (current_user_role() = 'owner');
create policy banned_phones_insert on public.banned_phones for insert to public with check (current_user_role() = 'owner');
create policy banned_phones_select on public.banned_phones for select to public
  using (current_user_role() = any (array['admin'::text, 'owner'::text]));
create policy banned_phones_update on public.banned_phones for update to public using (current_user_role() = 'owner');
alter table public.app_config_history enable row level security;
create policy app_config_history_owner_admin_read on public.app_config_history for select to authenticated
  using (coalesce(current_user_role(), '') = any (array['owner'::text, 'admin'::text]));
alter table public.family_names enable row level security;
create policy family_names_read on public.family_names for select to public using (auth.uid() is not null);
create policy family_names_write on public.family_names for all to public
  using (current_user_role() = any (array['owner'::text, 'admin'::text]))
  with check (current_user_role() = any (array['owner'::text, 'admin'::text]));
grant usage on schema public, auth to authenticated, anon;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage on all sequences in schema public to authenticated;
grant execute on all functions in schema public, auth to authenticated;
insert into public.profiles values
  ('${O}', 'owner', 'active', 'حسن المالك', 'حسن', '+96590000001'),
  ('${A}', 'admin', 'active', 'بدر المدير', 'بدر', '+96590000002'),
  ('${MON}', 'monitor', 'active', 'علي المراقب', 'علي', '+96590000003'),
  ('${S}', 'supervisor', 'active', 'سعد المشرف', 'سعد', '+96590000004'),
  ('${M}', 'member', 'active', 'أحمد العضو', 'أحمد', '+96590000005'),
  ('${FA}', 'admin', 'frozen', 'مدير مجمّد', 'مجمد', '+96590000006');
insert into public.device_tokens (member_id, token) values ('${O}', 'tok-owner'), ('${A}', 'tok-admin'), ('${M}', 'tok-member');
insert into public.device_revocations (member_id, device_id) values ('${M}', 'dev-member');
insert into public.banned_phones (phone_number) values ('96599887766'), ('96566012345');
insert into public.app_config_history (key) values ('site_url');
insert into public.family_names (name) values ('المحمدعلي');
`);

// ── أدوات ──
const as = async (who, sql, params) => {
  await db.exec(`select set_config('request.jwt.claim.sub', '${who}', false); set role authenticated;`);
  try { return await db.query(sql, params); } finally { await db.exec(`reset role; select set_config('request.jwt.claim.sub', '', false);`); }
};
const can = async (who, sql) => { try { await as(who, sql); return true; } catch (e) { return false; } };
const denied = async (who, sql) => { try { await as(who, sql); return false; } catch (e) { return e.code === '42501' || /row-level security|غير مصرح|permission/.test(e.message); } };
const rows = async (who, sql) => (await as(who, sql)).rows;
const one = async (who, sql) => (await rows(who, sql))[0];
const PATCHED = ['public.sms_admin_overview()', 'public.sms_balance_status()', 'public.sms_login_attempts(integer)',
  'public.app_config()', 'public.finish_kwtsms_send(text,text,text,numeric,numeric,text)', 'public.kwtsms_balance_check(numeric)',
  'public.log_login_attempt(text,text)'];
const md5s = async (sigs) => Object.fromEntries((await db.query(
  `select s, md5(pg_get_functiondef(s::regprocedure)) m from unnest($1::text[]) s`, [sigs])).rows.map(r => [r.s, r.m]));
const policies = async () => (await db.query(`select tablename || '.' || policyname p from pg_policies
  where schemaname = 'public' order by 1`)).rows.map(r => r.p).join(',');
const notifTargets = async (kind) => (await db.query(`select target_member_id t from public.notifications where kind = $1 order by 1`, [kind]))
  .rows.map(r => r.t);
const LIVE_MD5 = {
  'public.sms_balance_status()': 'cbcbca6e6bb5b00c7c223a7a854a486c',
  'public.app_config()': '415ace6352adde583c73321cfeac2bd8',
  'public.kwtsms_balance_check(numeric)': '9e4a4d0c274b5c9e26e3591d54861700',
  'public.log_login_attempt(text,text)': '79e8b1c1eaa9aa27c8fc699a1f72ce3e',
};

// ══════════ قبل الترحيل (= الحي) ══════════
const BEFORE = await md5s(PATCHED);
for (const [sig, m] of Object.entries(LIVE_MD5)) ok(BEFORE[sig] === m, `النسخة المحلية = الحية حرفياً: ${sig}`, BEFORE[sig]);
const POLICIES_BEFORE = await policies();
ok(await can(A, `select public.sms_balance_status()`), 'قبل: المدير يقرأ رصيد الرسائل');
ok(await can(A, `select public.sms_admin_overview()`), 'قبل: المدير يقرأ نظرة الرسائل');
ok((await one(A, `select public.sms_login_attempts(7) r`)).r.masked === true, 'قبل: المدير يقرأ محاولات الدخول (مخفية)');
ok((await one(A, `select public.app_config() c`)).c.meta !== undefined, 'قبل: المدير يتصفّح الإعدادات (meta)');
ok((await rows(A, `select * from public.device_tokens`)).length === 3, 'قبل: المدير يرى أجهزة الجميع');
ok((await rows(A, `select * from public.banned_phones`)).length === 2, 'قبل: المدير يرى الأرقام المحظورة');
ok(await can(A, `insert into public.family_names (name) values ('اختبار قبل')`), 'قبل: المدير يضيف اسم عائلة');
ok(await can(MON, `select public.approvals_report(now() - interval '7 days', now())`), 'قبل: المراقب يقرأ تقرير الموافقات');

// ══════════ الترحيل ══════════
await db.exec(MIG);
const AFTER = await md5s(PATCHED);
ok(PATCHED.every(s => AFTER[s] !== BEFORE[s]), 'كل الدوال السبع تغيّرت (سطر الشرط وحده)');
// أ) القراءة
ok(await denied(A, `select public.sms_balance_status()`), 'بعد: المدير ممنوع من رصيد الرسائل (42501)');
ok(await denied(A, `select public.sms_admin_overview()`), 'بعد: المدير ممنوع من نظرة الرسائل');
ok(await denied(A, `select public.sms_login_attempts(7)`), 'بعد: المدير ممنوع من محاولات الدخول');
ok(await denied(MON, `select public.sms_balance_status()`) && await denied(FA, `select public.sms_balance_status()`), 'بعد: المراقب والمدير المجمّد ممنوعان');
ok(await can(O, `select public.sms_balance_status()`), 'بعد: المالك يقرأ الرصيد');
ok((await one(O, `select public.sms_admin_overview() r`)).r.alerts.recipients === 'owner', 'بعد: «recipients» = owner');
ok((await one(O, `select public.sms_login_attempts(7) r`)).r.masked === false, 'بعد: المالك يقرأ محاولات الدخول كاملة');
const cfgA = (await one(A, `select public.app_config() c`)).c;
ok(cfgA.values?.sms_suspicious_per_hour === 5 && cfgA.scope === 'member', 'بعد: المدير يقرأ القيم كما كانت (يعمل بها التطبيق)');
ok(cfgA.meta === undefined && cfgA.can_edit === undefined && cfgA.categories === undefined, 'بعد: لا تصفّح للإعدادات عند المدير');
const cfgO = (await one(O, `select public.app_config() c`)).c;
ok(cfgO.can_edit === true && cfgO.meta?.site_url?.kind === 'text' && cfgO.categories?.length === 9, 'بعد: المالك يتصفّح كل شيء');
const cfgMon = (await one(MON, `select public.app_config() c`)).c;
ok(cfgMon.values?.site_url === 'https://almohali.com' && cfgMon.meta === undefined, 'بعد: المراقب القيم فقط (كما كان)');
// ب) التنبيهات للمالك وحده
await db.query(`select public.kwtsms_balance_check(9)`);
ok(JSON.stringify(await notifTargets('sms_balance_low')) === JSON.stringify([O]), 'بعد: تنبيه الرصيد العاجل للمالك وحده');
await db.query(`delete from public.notifications`);
await db.query(`select public.finish_kwtsms_send('e1', 'accepted', 'm1', 1, 17, null)`);
ok(JSON.stringify(await notifTargets('sms_balance_low')) === JSON.stringify([O]), 'بعد: تنبيه الرصيد بعد الإرسال للمالك وحده');
for (let i = 0; i < 5; i++) await db.query(`select public.log_login_attempt('96599887766', 'sent')`);
const sus = (await db.query(`select target_member_id t, body from public.notifications where kind = 'sms_suspicious'`)).rows;
ok(sus.length === 1 && sus[0].t === O && sus[0].body.endsWith('+965 99887766'), 'بعد: «محاولات دخول مريبة» للمالك وحده بالرقم كاملاً', JSON.stringify(sus));
// ج) الجداول
ok((await rows(A, `select member_id from public.device_tokens`)).map(r => r.member_id).join() === A, 'بعد: المدير يرى جهازه فقط');
ok((await rows(M, `select member_id from public.device_tokens`)).map(r => r.member_id).join() === M, 'بعد: العضو يرى جهازه (كما كان)');
ok((await rows(O, `select * from public.device_tokens`)).length === 3, 'بعد: المالك يرى كل الأجهزة');
await as(A, `delete from public.device_tokens where member_id = '${M}'`);
ok((await db.query(`select count(*)::int n from public.device_tokens where member_id = '${M}'`)).rows[0].n === 1, 'بعد: المدير لا يحذف جهاز غيره');
ok(await denied(A, `insert into public.device_revocations (member_id, device_id) values ('${M}', 'x')`), 'بعد: المدير لا يفكّ ربط جهاز غيره');
ok((await rows(A, `select * from public.device_revocations`)).length === 0, 'بعد: المدير لا يرى فكّ ربط غيره');
ok((await rows(M, `select * from public.device_revocations`)).length === 1, 'بعد: العضو يرى فكّ ربط جهازه (التطبيق يتحقق به)');
ok(await can(O, `insert into public.device_revocations (member_id, device_id) values ('${M}', 'dev-2')`), 'بعد: المالك يفكّ ربط جهاز');
await as(O, `delete from public.device_tokens where member_id = '${M}'`);
ok((await db.query(`select count(*)::int n from public.device_tokens where member_id = '${M}'`)).rows[0].n === 0, 'بعد: المالك يحذف جهاز عضو');
ok((await rows(A, `select * from public.banned_phones`)).length === 0, 'بعد: المدير لا يرى الأرقام المحظورة');
ok((await rows(O, `select * from public.banned_phones`)).length === 2, 'بعد: المالك يراها');
ok((await rows(A, `select * from public.app_config_history`)).length === 0 && (await rows(O, `select * from public.app_config_history`)).length === 1,
  'بعد: سجل الإعدادات للمالك وحده');
ok(await denied(A, `insert into public.family_names (name) values ('اختبار بعد')`), 'بعد: المدير لا يضيف اسم عائلة');
ok(await can(O, `insert into public.family_names (name) values ('اختبار المالك')`), 'بعد: المالك يضيف');
ok((await rows(M, `select * from public.family_names`)).length === 3, 'بعد: الأعضاء يقرؤون أسماء العوائل (التسجيل)');
// إعادة التطبيق تفشل بصوت (النص القديم لم يعد موجوداً) — لا تطبيق مزدوج صامت
let twice = null; try { await db.exec(MIG); } catch (e) { twice = e.message; }
ok(twice !== null && /expected the old text once, found 0/.test(twice), 'تطبيقه مرتين يفشل بوضوح', twice);
ok(JSON.stringify(await md5s(PATCHED)) === JSON.stringify(AFTER), 'والفشل لم يغيّر شيئاً');

// ══════════ التراجع ══════════
await db.exec(RB);
const ROLLED = await md5s(PATCHED);
ok(PATCHED.every(s => ROLLED[s] === BEFORE[s]), 'التراجع: نصوص الدوال السبع كما كانت حرفياً (نفس md5)');
ok((await policies()) === POLICIES_BEFORE, 'التراجع: السياسات بأسمائها كما كانت');
ok(await can(A, `select public.sms_balance_status()`) && (await one(A, `select public.app_config() c`)).c.meta !== undefined,
  'التراجع: المدير يقرأ كما كان');
ok((await rows(A, `select * from public.banned_phones`)).length === 2, 'التراجع: المدير يرى الأرقام المحظورة');
await db.query(`delete from public.notifications`);
await db.query(`select public.kwtsms_balance_check(9)`);
ok((await notifTargets('sms_balance_low')).length === 2, 'التراجع: التنبيه للمالك والمدير كما كان');
await db.exec(MIG);
ok(JSON.stringify(await md5s(PATCHED)) === JSON.stringify(AFTER), 'يُطبَّق من جديد بعد التراجع (نفس النتيجة)');

// ══════════ «المؤشرات» ليست للمراقب ══════════
const R0 = (await md5s(['public.approvals_report(timestamptz,timestamptz)']))['public.approvals_report(timestamptz,timestamptz)'];
await db.exec(MIG2);
ok(await denied(MON, `select public.approvals_report(now() - interval '7 days', now())`), 'المؤشرات: المراقب ممنوع من تقرير الموافقات');
ok(await can(A, `select public.approvals_report(now() - interval '7 days', now())`) &&
   await can(O, `select public.approvals_report(now() - interval '7 days', now())`), 'المؤشرات: المالك والمدير كما كانا');
ok(await denied(S, `select public.approvals_report(now() - interval '7 days', now())`), 'المؤشرات: المشرف ممنوع (كما كان)');
await db.exec(RB2);
ok((await md5s(['public.approvals_report(timestamptz,timestamptz)']))['public.approvals_report(timestamptz,timestamptz)'] === R0,
  'المؤشرات — التراجع: النص كما كان حرفياً');
ok(await can(MON, `select public.approvals_report(now() - interval '7 days', now())`), 'المؤشرات — التراجع: المراقب يقرأ كما كان');

console.log(`\n${pass} نجح، ${fail} فشل`);
process.exit(fail ? 1 : 0);
