// تجربة 20261021080000 («اعرض الرمز» للمالك وحده) على قاعدة محلية معزولة — لا تلمس السيرفر.
// ١) «قبل» = ترحيلات KWT العشرة (كلها على الحي). صلاحيات Supabase الافتراضية مفعّلة قبل الترحيل حتى يُثبت أن السحب يعمل.
// ٢) المالك وحده يقرأ (المدير/المراقب/العضو/المجمّد/المعلّق ← 42501)، الخدمة وحدها تحفظ، الجدولان لا يصلهما أحد.
// ٣) آخر رمز فقط، يبطل بالانتهاء أو بالدخول بعده، كل «عرض» يُسجَّل بلا الرمز، التنظيف والحفظ المحدود للسجل.
// ٤) دوال KWT القائمة وقراءة «محاولات الدخول» لم تتغيّر، ثم التراجع يمسح كل شيء ويعيدها كما كانت.
// التشغيل: cd supabase/tests/family_links && node owner_login_code.test.mjs
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
process.on('unhandledRejection', e => { console.log('خطأ:', e.message, e.where ?? '', (e.query ?? '').slice(0, 300)); process.exit(2); });

const REPO = fileURLToPath(new URL('../../', import.meta.url));
const r = f => readFileSync(`${REPO}/${f}`, 'utf8');
const MIG = r('migrations/20261021080000_owner_login_code.sql');
const RB = r('rollback/20261021080000_owner_login_code_rollback.sql');
const KWT_FNS = ['public.finish_kwtsms_send(text,text,text,numeric,numeric,text)', 'public.reserve_kwtsms_send(text,text,boolean,integer)',
  'public.log_login_attempt(text,text)', 'public.kwtsms_balance_check(numeric)', 'public.record_kwtsms_balance(numeric)',
  'public.sms_balance_status()', 'public.sms_admin_overview()', 'public.sms_login_attempts(integer)', 'public.login_attempt_profile_id(text)'];

let pass = 0, fail = 0;
const ok = (c, m, x = '') => { c ? pass++ : fail++; console.log(`${c ? '✅' : '❌'} ${m}${!c && x !== '' ? ' — ' + x : ''}`); };
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const P = { O: id(1), A: id(2), A2: id(3), FA: id(4), M: id(5), MON: id(6), K: id(10), N: id(11) };

const db = new PGlite();
await db.exec(`
do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role bypassrls; end if;
end $$;
grant usage on schema public to anon, authenticated, service_role;
create schema auth;
create table auth.users (id uuid primary key, phone text, raw_app_meta_data jsonb default '{}', last_sign_in_at timestamptz);
create table public.profiles (id uuid primary key, role text, status text, phone_number text, full_name text, first_name text,
  created_at timestamptz default now());
create table public.notifications (id uuid primary key default gen_random_uuid(), target_member_id uuid,
  created_by uuid, title text not null, body text not null, kind text not null default 'general', is_read boolean not null default false,
  created_at timestamptz not null default now(), details jsonb, subject_member_id uuid);
create or replace function public.current_user_role() returns text language sql stable as $$
  select nullif(current_setting('test.role', true), '') $$;
grant execute on function public.current_user_role() to anon, authenticated, service_role;
create table public.app_settings (id uuid primary key default gen_random_uuid(),
  allow_new_registrations boolean not null default true, updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id));
insert into public.app_settings default values;
-- كما في الحي: السرّ في private.app_secrets (لا وصول للتطبيقات)، pg_net، pg_cron 1.6.4
create schema private;
create table private.app_secrets (key text primary key, value text);
create schema net;
create table net.calls (id bigserial primary key, url text, body jsonb, headers jsonb, timeout_ms int);
create function net.http_post(url text, body jsonb default '{}'::jsonb, params jsonb default '{}'::jsonb,
  headers jsonb default '{"Content-Type": "application/json"}'::jsonb, timeout_milliseconds integer default 5000)
returns bigint language plpgsql as $f$
declare v bigint;
begin
  if current_setting('test.net_down', true) = 'on' then raise exception 'pg_net queue unavailable'; end if;
  insert into net.calls (url, body, headers, timeout_ms) values (url, body, headers, timeout_milliseconds) returning id into v;
  return v;
end $f$;
-- مثل trigger_push_on_notification: كل إشعار يمر بـ net.http_post (فيصير عطل pg_net عطلاً في الإدراج)
create function public.test_push_on_notification() returns trigger language plpgsql security definer as $f$
begin perform net.http_post(url := 'https://push.test/push-on-notification', body := jsonb_build_object('kind', new.kind)); return new; end $f$;
create trigger trg_push_on_notification after insert on public.notifications
  for each row execute function public.test_push_on_notification();
create schema cron;
create table cron.job (jobid bigserial primary key, schedule text not null, command text not null, active boolean default true,
  jobname text unique);
create function cron.schedule(job_name text, schedule text, command text) returns bigint language plpgsql as $c$
declare j bigint;
begin
  insert into cron.job (jobname, schedule, command) values (job_name, schedule, command)
  on conflict (jobname) do update set schedule = excluded.schedule, command = excluded.command returning jobid into j;
  return j;
end $c$;
create function cron.unschedule(job_name text) returns boolean language plpgsql as $c$
begin
  delete from cron.job where jobname = job_name;
  if not found then raise exception 'could not find valid entry for job ''%''', job_name; end if;
  return true;
end $c$;
insert into public.profiles (id, role, status, phone_number, full_name, first_name) values
  ('${P.O}',   'owner',   'active', '+96590000001', 'المالك', 'مالك'),
  ('${P.A}',   'admin',   'active', '+96590000002', 'المدير', 'بدر'),
  ('${P.A2}',  'admin',   'active', '+96590000003', 'مدير ثاني', 'علي'),
  ('${P.FA}',  'admin',   'frozen', '+96590000004', 'مدير مجمّد', 'مجمد'),
  ('${P.M}',   'member',  'active', '+96590000005', 'عضو', 'حسن'),
  ('${P.MON}', 'monitor', 'active', '+96590000006', 'مراقب', 'مراقب'),
  ('${P.K}',   'member',  'active', '+96550001234', 'كاظم علي حسن المحمدعلي', 'كاظم'),
  ('${P.N}',   'member',  'active', '+96560002222', '   ', 'نوح');
insert into auth.users (id, phone) values ('${P.K}', '96550001234');
`);
for (const f of ['20261019200000_kwtsms_delivery_guard', '20261019210000_kwtsms_low_balance_alert', '20261019220000_kwtsms_cooldown_one_minute',
  '20261019230000_kwtsms_urgent_alert_12h', '20261020150000_kwtsms_daily_stats', '20261020151000_kwtsms_admin_overview',
  '20261020160000_login_attempts', '20261020170000_kwtsms_editable_limits', '20261020180000_kwtsms_wait_min_30']) await db.exec(r(`migrations/${f}.sql`));
// الحي طُبّق بلا تعليقات: log_login_attempt = نص الحي من ملف التراجع (يثبت أيضاً أن ملف التراجع = الحي حرفياً)
await db.exec(r('migrations/20261020190000_kwtsms_daily_check_and_suspicious.sql'));
await db.exec(`create or replace function public.current_profile_id() returns uuid language sql stable as $$
  select nullif(current_setting('test.pid', true), '')::uuid $$;
grant execute on function public.current_profile_id() to anon, authenticated, service_role;`);

const one = async (q, p = []) => (await db.query(q, p)).rows[0];
const md5 = async sig => (await one(`select md5(pg_get_functiondef('${sig}'::regprocedure)) m`)).m;
const priv = async q => (await one(`select (select ${q}) x`)).x;
await db.exec(`alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;`);
const as = async (role, sql, params = [], appRole = '', pid = '') => {
  await db.query(`select set_config('test.role', $1, false), set_config('test.pid', $2, false)`, [appRole, pid]);
  await db.exec(`set role ${role}`);
  try { return { ok: true, rows: (await db.query(sql, params)).rows }; }
  catch (e) { return { ok: false, err: e.message, code: e.code }; }
  finally { await db.exec('reset role'); await db.query(`select set_config('test.role', '', false), set_config('test.pid', '', false)`); }
};
const store = (phone, code) => as('service_role', `select public.store_login_code($1, $2)`, [phone, code]);
const reveal = async (phone, role = 'owner', pid = P.O) => {
  const res = await as('authenticated', `select public.owner_reveal_login_code($1) j`, [phone], role, pid);
  return res.ok ? res.rows[0].j : res;
};
const codes = async (role = 'owner', days = 7) => {
  const res = await as('authenticated', `select public.owner_login_codes($1) j`, [days], role, P.O);
  return res.ok ? res.rows[0].j : res;
};
const attempts = async roleName => {
  const res = await as('authenticated', `select public.sms_login_attempts(7) j`, [], roleName);
  const o = res.rows[0].j; delete o.generated_at; return o;
};

// ── «قبل» ──
await as('service_role', `select public.log_login_attempt('96550001234', 'sent')`);
await as('service_role', `select public.log_login_attempt('96560002222', 'failed')`);
const BEFORE = {}; for (const sig of KWT_FNS) BEFORE[sig] = await md5(sig);
const READ_BEFORE = JSON.stringify({ owner: await attempts('owner'), admin: await attempts('admin') });
const JOBS_BEFORE = (await one(`select string_agg(jobname, ',' order by jobname) j from cron.job`)).j;

// ══════════ الترحيل ══════════
await db.exec(MIG);
for (const sig of KWT_FNS) ok(await md5(sig) === BEFORE[sig], `بعد: ${sig.split('(')[0].slice(7)} ما تغيّرت`);
ok(JSON.stringify({ owner: await attempts('owner'), admin: await attempts('admin') }) === READ_BEFORE, 'بعد: قراءة «محاولات الدخول» نفسها حرفياً');

// ── الصلاحيات ──
for (const who of ['anon', 'authenticated', 'service_role']) {
  for (const t of ['private.login_codes', 'private.login_code_views'])
    ok(!(await priv(`has_table_privilege('${who}', '${t}', 'select') or has_table_privilege('${who}', '${t}', 'insert')`)), `${t}: لا قراءة ولا كتابة لـ ${who}`);
  ok(!(await priv(`has_function_privilege('${who}', 'public.cleanup_login_codes()', 'execute')`)), `cleanup_login_codes: ممنوعة على ${who}`);
  ok(!(await priv(`has_function_privilege('${who}', 'private.login_code_valid(text,timestamptz,timestamptz)', 'execute')`)), `login_code_valid: ممنوعة على ${who}`);
}
for (const who of ['anon', 'authenticated']) ok(!(await priv(`has_function_privilege('${who}', 'public.store_login_code(text,text)', 'execute')`)), `store_login_code: ممنوعة على ${who}`);
ok(await priv(`has_function_privilege('service_role', 'public.store_login_code(text,text)', 'execute')`), 'store_login_code: للخدمة');
for (const f of ['public.owner_login_codes(integer)', 'public.owner_reveal_login_code(text)'])
  ok(!(await priv(`has_function_privilege('anon', '${f}', 'execute')`)), `${f.split('(')[0].slice(7)}: ممنوعة على anon`);
let res = await as('authenticated', `select * from private.login_codes`, [], 'owner', P.O);
ok(!res.ok && /permission denied/.test(res.err), 'حتى المالك لا يقرأ الجدول مباشرة', res.err);
res = await as('authenticated', `select public.store_login_code('96550001234', '123456')`, [], 'owner', P.O);
ok(!res.ok && /permission denied/.test(res.err), 'المالك لا يحفظ رمزاً من التطبيق', res.err);

// ── الحفظ: تحقق ──
for (const [p, c, why] of [['96550001234', '12345', 'رمز ٥ خانات'], ['96550001234', '12a456', 'حروف'], ['96550001234', null, 'بلا رمز'],
  ['+96550001234', '123456', 'رقم بعلامة +'], ['96530001234', '123456', 'رقم غير كويتي الصيغة'], [null, '123456', 'بلا رقم']]) {
  res = await store(p, c);
  ok(!res.ok && res.code === '22023', `store_login_code ترفض: ${why}`, res.err);
}
ok(Number(await priv(`count(*)::int from private.login_codes`)) === 0, 'لا شيء حُفظ من المرفوض');

// ── المالك وحده ──
ok((await store('96550001234', '482913')).ok, 'الخدمة تحفظ رمزاً');
for (const role of ['admin', 'monitor', 'supervisor', 'member', 'frozen', 'pending', '']) {
  const x = await reveal('+96550001234', role, P.A);
  ok(x.ok === false && x.code === '42501', `«اعرض الرمز» ممنوع على ${role || 'غير المسجّل'}`, x.err);
  const y = await codes(role);
  ok(y.ok === false && y.code === '42501', `قائمة الرموز ممنوعة على ${role || 'غير المسجّل'}`, y.err);
}
ok(Number(await priv(`count(*)::int from private.login_code_views`)) === 0, 'المرفوض لا يُسجَّل عرضاً (ولا يرى شيئاً)');
let list = await codes();
ok(list.codes.length === 1 && list.codes[0].phone_e164 === '+96550001234' && list.codes[0].expires_at, 'القائمة: الرقم له رمز صالح', JSON.stringify(list));
ok(!JSON.stringify(list).includes('482913'), 'القائمة لا تحمل الرمز نفسه');
ok(list.views.length === 0, 'القائمة: لا عرض بعد');

let x = await reveal('+96550001234');
ok(x.status === 'shown' && x.code === '482913' && x.expires_at, '«اعرض الرمز» للمالك ← الرمز ووقت انتهائه', JSON.stringify(x));
x = await reveal('0096550001234');
ok(x.status === 'shown' && x.code === '482913', 'يقبل 00965 و965 و+965');
let v = await one(`select phone, viewed_by, result from private.login_code_views order by id limit 1`);
ok(v.phone === '96550001234' && v.viewed_by === P.O && v.result === 'shown', 'العرض مُسجَّل (الرقم، المالك، النتيجة)', JSON.stringify(v));
ok(Number(await priv(`count(*)::int from information_schema.columns where table_schema = 'private' and table_name = 'login_code_views' and column_name = 'code'`)) === 0, 'السجل بلا عمود رمز');
list = await codes();
ok(list.views.length === 1 && list.views[0].count === 2 && list.views[0].phone_e164 === '+96550001234', 'القائمة: آخر عرض وعدده', JSON.stringify(list.views));

// ── آخر رمز فقط ──
await store('96550001234', '771100');
ok(Number(await priv(`count(*)::int from private.login_codes`)) === 1, 'رمز جديد يحلّ محل القديم (سطر واحد للرقم)');
x = await reveal('96550001234');
ok(x.status === 'shown' && x.code === '771100', 'يُعرض الأحدث فقط');

// ── يبطل بالدخول بعده ──
await db.exec(`update auth.users set last_sign_in_at = now() + interval '1 second' where phone = '96550001234'`);
x = await reveal('96550001234');
ok(x.status === 'used' && x.code === null && x.expires_at === null, 'دخل بعد الرمز ← «used» بلا رمز', JSON.stringify(x));
ok((await codes()).codes.length === 0, 'والقائمة تخفيه');
await db.exec(`update auth.users set last_sign_in_at = now() - interval '1 day' where phone = '96550001234'`);
ok((await reveal('96550001234')).status === 'shown', 'دخول قديم (قبل الرمز) لا يبطله');

// ── يبطل بالانتهاء ──
await store('96560002222', '300300');
await db.exec(`update private.login_codes set expires_at = now() - interval '1 second', sent_at = now() - interval '301 seconds' where phone = '96560002222'`);
x = await reveal('+96560002222');
ok(x.status === 'expired' && x.code === null, 'انتهت الخمس دقائق ← «expired» بلا رمز', JSON.stringify(x));
ok((await codes()).codes.every(c => c.phone_e164 !== '+96560002222'), 'والقائمة تخفيه');
x = await reveal('+96599990001');
ok(x.status === 'none' && x.code === null, 'رقم بلا رمز ← «none»');
res = await as('authenticated', `select public.owner_reveal_login_code('12345')`, [], 'owner', P.O);
ok(!res.ok && res.code === '22023', 'رقم غير صالح ← 22023 (بلا تسجيل)', res.err);
ok(Number(await priv(`count(*)::int from private.login_code_views where result = 'expired'`)) === 1
  && Number(await priv(`count(*)::int from private.login_code_views where result = 'none'`)) === 1
  && Number(await priv(`count(*)::int from private.login_code_views where result = 'used'`)) === 1, 'كل نتيجة تُسجَّل');

// ── التنظيف ──
let job = await one(`select schedule, command from cron.job where jobname = 'login-codes-cleanup'`);
ok(job && job.schedule === '*/5 * * * *' && job.command === 'select public.cleanup_login_codes()', 'pg_cron: «login-codes-cleanup» كل ٥ دقائق', JSON.stringify(job));
ok((await store('96599991111', '111111')).ok, 'حفظ رمز ثالث');
await db.exec(`insert into auth.users (id, phone, last_sign_in_at) values ('${id(70)}', '96599991111', now() + interval '1 second');
  insert into private.login_codes (phone, code, sent_at, expires_at) values ('96560002222', '300300', now() - interval '301 seconds', now() - interval '1 second')`);
const n = (await one(`select public.cleanup_login_codes() n`)).n;
ok(n === 2 && Number(await priv(`count(*)::int from private.login_codes`)) === 1, 'التنظيف يمسح المنتهي والمستعمل ويُبقي الصالح', n);
ok(Number(await priv(`count(*)::int from private.login_codes where phone = '96550001234'`)) === 1, 'الصالح باقٍ');
// تخزين جديد يمسح المنتهي أيضاً
await db.exec(`update private.login_codes set expires_at = now() - interval '1 second'`);
await store('96560002222', '222222');
ok(Number(await priv(`count(*)::int from private.login_codes`)) === 1, 'الحفظ يمسح المنتهي');
// سجل العرض بمدة «محاولات الدخول»
await db.exec(`insert into private.login_code_views (phone, viewed_by, viewed_at, result)
  select '96550001234', '${P.O}', now() - interval '31 days' - (i || ' minutes')::interval, 'shown' from generate_series(1, 250) i`);
await store('96560002222', '333333');
ok(Number(await priv(`count(*)::int from private.login_code_views where viewed_at < now() - interval '30 days'`)) === 50, 'سجل العرض: حذف محدود (٢٠٠) بعد ٣٠ يوماً');
await db.exec(`update public.app_settings set login_attempts_retention_days = 90`);
await db.exec(`insert into private.login_code_views (phone, viewed_by, viewed_at, result) values ('96550001234', '${P.O}', now() - interval '40 days', 'shown')`);
const before40 = Number(await priv(`count(*)::int from private.login_code_views`));
await store('96560002222', '444444');
ok(Number(await priv(`count(*)::int from private.login_code_views`)) === before40, 'سجل العرض يتبع مدة الحفظ المختارة (٩٠ يوماً ← لا حذف)');

// ══════════ التراجع ══════════
await db.exec(RB);
ok(Number(await priv(`count(*)::int from pg_proc where proname in ('store_login_code', 'owner_login_codes', 'owner_reveal_login_code', 'cleanup_login_codes', 'login_code_valid')`)) === 0, 'التراجع: الدوال حُذفت');
ok(Number(await priv(`count(*)::int from pg_class c join pg_namespace s on s.oid = c.relnamespace where s.nspname = 'private' and c.relname like 'login_code%'`)) === 0, 'التراجع: الجدولان (والرموز) حُذفت');
ok((await one(`select string_agg(jobname, ',' order by jobname) j from cron.job`)).j === JOBS_BEFORE, 'التراجع: المهمة أُلغيت والبقية كما هي');
for (const sig of KWT_FNS) ok(await md5(sig) === BEFORE[sig], `التراجع: ${sig.split('(')[0].slice(7)} كما كانت`);
res = await store('96550001234', '123456');
ok(!res.ok && /does not exist/.test(res.err), 'بعد التراجع: نداء الدالة الطرفية يفشل (فتبلعه، والإرسال لا يتأثر)', res.err);
res = await db.exec(RB).then(() => ({ ok: true }), e => ({ ok: false, err: e.message }));
ok(res.ok, 'التراجع مرتين بلا خطأ', res.err);
await db.exec(MIG);
ok((await store('96550001234', '123456')).ok && (await reveal('96550001234')).code === '123456', 'إعادة التطبيق بعد التراجع تعمل');

console.log(`\nالنتيجة: ${pass} نجحت، ${fail} فشلت`);
process.exit(fail ? 1 : 0);
