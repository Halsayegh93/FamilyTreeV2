// تجربة 20261020190000 (فحص رصيد KWT اليومي + تنبيه المحاولات المريبة) على قاعدة محلية معزولة — لا تلمس السيرفر.
// ١) «قبل» = ترحيلات KWT الثمانية + log_login_attempt بنص الحي حرفياً (من ملف التراجع، md5 = pg_get_functiondef على
//    الحي ٢٠٢٦-١٠-٢٠). صلاحيات Supabase الافتراضية مفعّلة قبل الترحيل حتى يُثبت أن السحب يعمل.
// ٢) الميزة ٣: kwtsms_balance_check = نفس قواعد finish_kwtsms_send (العتبتان، فواصل التكرار من app_settings، النص،
//    المستلمون)، تكرار مشترك بين المسارين، الحفظ في السجل اليومي، المهمة ونداء pg_net بالسرّ.
// ٣) الميزة ٤: ٥ محاولات في ٦٠ دقيقة ← تنبيه مرة كل ١٢ ساعة لكل رقم، المالك كامل والمدير مخفي، الخطأ لا يصعد.
// ٤) السلوك القائم لم يتغير (نفس الدوال حرفياً، نفس قراءة «محاولات الدخول»)، ثم التراجع يعيد الحي حرفياً.
// التشغيل: cd supabase/tests/family_links && node kwtsms_daily_check.test.mjs
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
process.on('unhandledRejection', e => { console.log('خطأ:', e.message, e.where ?? '', (e.query ?? '').slice(0, 300)); process.exit(2); });

const REPO = fileURLToPath(new URL('../../', import.meta.url));
const r = f => readFileSync(`${REPO}/${f}`, 'utf8');
const MIG = r('migrations/20261020190000_kwtsms_daily_check_and_suspicious.sql');
const RB = r('rollback/20261020190000_kwtsms_daily_check_and_suspicious_rollback.sql');
// الحي (pg_get_functiondef، قراءة فقط ٢٠٢٦-١٠-٢٠)
const LIVE_LOG_MD5 = 'e2df85b708ca82e8034b169f5b1882cc';
const LIVE_LOG_ACL = '{postgres=X/postgres,service_role=X/postgres}';
// دوال KWT القائمة — الترحيل وتراجعه لا يلمسانها
const KWT_FNS = ['public.finish_kwtsms_send(text,text,text,numeric,numeric,text)', 'public.reserve_kwtsms_send(text,text,boolean,integer)',
  'public.reserve_kwtsms_admin_test(text,text,boolean)', 'public.record_kwtsms_balance(numeric)', 'public.sms_balance_status()',
  'public.sms_admin_overview()', 'public.sms_login_attempts(integer)', 'public.login_attempt_profile_id(text)',
  'public.set_kwtsms_sender(text,uuid)', 'public.record_kwtsms_delivery_status(text,text)'];

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
await db.exec(RB.slice(RB.indexOf('CREATE OR REPLACE FUNCTION public.log_login_attempt'), RB.indexOf('-- ═══ ٤) العمود')));

const one = async (q, p = []) => (await db.query(q, p)).rows[0];
const md5 = async sig => (await one(`select md5(pg_get_functiondef('${sig}'::regprocedure)) m`)).m;
const acl = async sig => (await one(`select proacl::text a from pg_proc where oid = '${sig}'::regprocedure`)).a;
const priv = async q => (await one(`select (select ${q}) x`)).x;
const BEFORE = {}; for (const sig of KWT_FNS) BEFORE[sig] = await md5(sig);
ok(await md5('public.log_login_attempt(text,text)') === LIVE_LOG_MD5, 'قبل: log_login_attempt = الحي حرفياً');

// صلاحيات Supabase الافتراضية (كما في الحي) — كل دالة/جدول جديد يُمنح للتطبيقات
await db.exec(`alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;`);
// الكتابة الافتراضية للخدمة (الدالة الطرفية)؛ test.role = دور التطبيق لـ current_user_role
const as = async (role, sql, params = [], appRole = '') => {
  await db.query(`select set_config('test.role', $1, false)`, [appRole]);
  await db.exec(`set role ${role}`);
  try { return { ok: true, rows: (await db.query(sql, params)).rows }; }
  catch (e) { return { ok: false, err: e.message, code: e.code }; }
  finally { await db.exec('reset role'); await db.query(`select set_config('test.role', '', false)`); }
};
const log = (phone, outcome = 'sent') => as('service_role', `select public.log_login_attempt($1, $2)`, [phone, outcome]);
const attempts = async (roleName, days = 7) => {
  const res = await as('authenticated', `select public.sms_login_attempts($1) j`, [days], roleName);
  if (!res.ok) throw Error(res.err);
  const o = res.rows[0].j; delete o.generated_at; return o;
};

// ── «قبل»: بيانات + قراءة «محاولات الدخول» بالدالة الحية (تُقارن بعد الترحيل) ──
for (let i = 0; i < 3; i++) await log('96550001234', i ? 'blocked' : 'sent');
for (let i = 0; i < 6; i++) await log('96599990001', 'blocked');   // ٦ في دقيقة بالدالة القديمة (بلا تنبيه)
await log('96560002222', 'failed');
await db.exec(`update public.login_attempts set created_at = created_at - interval '2 hours'`);
const READ_BEFORE = { owner: await attempts('owner'), admin: await attempts('admin') };
ok(Number(await priv(`count(*)::int from public.notifications`)) === 0, 'قبل: الدالة الحية لا تنبّه');

// ══════════ الترحيل ══════════
await db.exec(MIG);
for (const sig of KWT_FNS) ok(await md5(sig) === BEFORE[sig], `بعد: ${sig.split('(')[0].slice(7)} ما تغيّرت`);
ok(JSON.stringify({ owner: await attempts('owner'), admin: await attempts('admin') }) === JSON.stringify(READ_BEFORE),
  'بعد: قراءة «محاولات الدخول» (المالك والمدير) نفسها حرفياً');

// ── الصلاحيات ──
ok(await acl('public.log_login_attempt(text,text)') === LIVE_LOG_ACL, 'log_login_attempt: نفس صلاحيات الحي (الخدمة فقط)',
  await acl('public.log_login_attempt(text,text)'));
for (const who of ['anon', 'authenticated']) {
  ok(!(await priv(`has_function_privilege('${who}', 'public.kwtsms_balance_check(numeric)', 'execute')`)), `kwtsms_balance_check: ممنوعة على ${who}`);
  ok(!(await priv(`has_function_privilege('${who}', 'public.kwtsms_daily_balance_job()', 'execute')`)), `kwtsms_daily_balance_job: ممنوعة على ${who}`);
}
ok(await priv(`has_function_privilege('service_role', 'public.kwtsms_balance_check(numeric)', 'execute')`), 'kwtsms_balance_check: للخدمة');
ok(!(await priv(`has_function_privilege('service_role', 'public.kwtsms_daily_balance_job()', 'execute')`)), 'kwtsms_daily_balance_job: ولا للخدمة (المهمة المجدولة فقط)');
let res = await as('authenticated', `select public.kwtsms_balance_check(5)`, [], 'owner');
ok(!res.ok && /permission denied/.test(res.err), 'حتى المالك لا يستدعي الفحص من التطبيق', res.err);
res = await as('authenticated', `select public.kwtsms_daily_balance_job()`, [], 'owner');
ok(!res.ok && /permission denied/.test(res.err), 'ولا المهمة', res.err);
ok(await priv(`column_default from information_schema.columns where table_name = 'login_attempts' and column_name = 'alerted'`) === 'false'
  && await priv(`is_nullable from information_schema.columns where table_name = 'login_attempts' and column_name = 'alerted'`) === 'NO',
  'login_attempts.alerted: false افتراضياً وغير فارغ');
ok(!(await priv(`has_table_privilege('authenticated', 'public.login_attempts', 'select')`)), 'login_attempts ما زال مقفولاً عن التطبيقات');

// ── الجدولة ──
let job = await one(`select schedule, command, active from cron.job where jobname = 'kwtsms-daily-balance'`);
ok(job && job.schedule === '0 6 * * *' && job.command === 'select public.kwtsms_daily_balance_job()' && job.active,
  'pg_cron: «kwtsms-daily-balance» ٠٦:٠٠ UTC (٠٩:٠٠ الكويت)', JSON.stringify(job));

// ══════════ الميزة ٣: الفحص اليومي ══════════
const notes = (kind = 'sms_balance_low') => db.query(`select target_member_id t, title, body, created_by, is_read from public.notifications
  where kind = $1 order by created_at, target_member_id`, [kind]).then(x => x.rows);
const check = async bal => {
  const res = await as('service_role', `select public.kwtsms_balance_check($1) j`, [bal]);
  return res.ok ? res.rows[0].j : res;
};
const ageNotes = (h, extra = '') => db.exec(`update public.notifications set created_at = created_at - interval '${h} hours' where kind = 'sms_balance_low' ${extra}`);
const LOW = 'رصيد رسائل الدخول قليل', URGENT = 'عاجل: رصيد رسائل الدخول قارب يخلص';
const body = n => `باقي ${n} نقطة في KWT SMS — كل رمز دخول بنقطة. اشحن الرصيد حتى ما يوقف تسجيل الدخول.`;
const today = async () => one(`select last_balance::float b, balance_at from public.kwtsms_daily_stats
  where day = (now() at time zone 'Asia/Kuwait')::date`);

let j = await check(120);
ok(j.recorded === true && j.state === 'ok' && j.alerted === false, 'رصيد ١٢٠: يُحفظ، «جيد»، بلا تنبيه', JSON.stringify(j));
ok((await today()).b === 120, 'السجل اليومي: آخر رصيد ١٢٠ (يوم بلا رسائل)');
await db.query(`select set_config('test.role', 'owner', false)`);
let ov = (await one(`select public.sms_admin_overview() o`)).o;
await db.query(`select set_config('test.role', '', false)`);
ok(Number(ov.balance) === 120 && ov.balance_state === 'ok', 'صفحة الإدارة تعرض رصيد الفحص', JSON.stringify([ov.balance, ov.balance_state]));
ok((await notes()).length === 0, 'لا إشعار');

j = await check(40);
let n = await notes();
ok(j.state === 'low' && j.alerted === true, 'رصيد ٤٠ (< ٥٠): «منخفض» وتنبيه', JSON.stringify(j));
ok(n.length === 3 && n.every(x => x.title === LOW && x.body === body(40) && x.created_by === null && x.is_read === false),
  'التنبيه: نفس العنوان والنص، بلا مرسل، غير مقروء', JSON.stringify(n[0]));
ok(JSON.stringify(n.map(x => x.t).sort()) === JSON.stringify([P.O, P.A, P.A2].sort()), 'المستلمون: المالك والمدراء المفعّلون فقط (لا المجمّد ولا غيرهم)');
ok((await today()).b === 40, 'السجل اليومي: آخر رصيد ٤٠');
j = await check(35);
ok(j.state === 'low' && j.alerted === false && (await notes()).length === 3, 'رصيد ٣٥ بعدها: لا تكرار خلال ٢٤ ساعة');
await ageNotes(23);
ok((await check(30)).alerted === false, 'بعد ٢٣ ساعة: ما زال لا تكرار');
await ageNotes(2);
j = await check(30);
ok(j.alerted === true && (await notes()).filter(x => x.body === body(30)).length === 3, 'بعد ٢٥ ساعة: تنبيه «منخفض» جديد');

j = await check(8);
n = await notes();
ok(j.state === 'urgent' && j.alerted === true && n.filter(x => x.title === URGENT && x.body === body(8)).length === 3,
  'رصيد ٨ (< ١٠): «عاجل» حتى مع تنبيه «منخفض» حديث', JSON.stringify(j));
ok((await check(6)).alerted === false, 'العاجل لا يتكرر خلال ١٢ ساعة');
await ageNotes(11, `and title like '%عاجل%'`);
ok((await check(6)).alerted === false, 'بعد ١١ ساعة: لا');
await ageNotes(2, `and title like '%عاجل%'`);
j = await check(5);
ok(j.alerted === true && (await notes()).filter(x => x.body === body(5)).length === 3, 'بعد ١٣ ساعة: عاجل جديد');
ok((await check(40)).alerted === false, '«منخفض» بعد «عاجل» حديث: لا تكرار (أي تنبيه رصيد خلال ٢٤ ساعة يكفي — كالحي)');

// الفواصل والعتبات من app_settings (المالك يعدّلها)
await db.exec(`delete from public.notifications; update public.app_settings set sms_low_threshold = 200, sms_urgent_threshold = 100,
  sms_low_repeat_hours = 2, sms_urgent_repeat_hours = 1`);
j = await check(150);
ok(j.state === 'low' && j.alerted === true, 'عتبة «منخفض» ٢٠٠ من الإعدادات: ١٥٠ ينبّه');
await ageNotes(1);
ok((await check(150)).alerted === false, 'فاصل «منخفض» ساعتان: بعد ساعة لا');
await ageNotes(1.5);
ok((await check(150)).alerted === true, '... وبعد ساعتين ونص نعم');
j = await check(99);
ok(j.state === 'urgent' && j.alerted === true, 'عتبة «عاجل» ١٠٠: ٩٩ عاجل');
await ageNotes(1.1, `and title like '%عاجل%'`);
ok((await check(99)).alerted === true, 'فاصل «عاجل» ساعة: بعد ساعة وشوي ينبّه');
await db.exec(`delete from public.notifications; update public.app_settings set sms_urgent_threshold = 0, sms_low_threshold = 0`);
j = await check(0);
ok(j.state === 'ok' && j.alerted === false && (await notes()).length === 0, 'عتبة «منخفض» = ٠ تطفئ التنبيه (حتى برصيد صفر)');
await db.exec(`update public.app_settings set sms_low_threshold = 50, sms_urgent_threshold = 10, sms_low_repeat_hours = 24, sms_urgent_repeat_hours = 12`);

// قيم غير صالحة: لا حفظ ولا تنبيه
const statsBefore = JSON.stringify(await today());
for (const bad of [-1, null, 100000001]) {
  res = await as('service_role', `select public.kwtsms_balance_check($1)`, [bad]);
  ok(!res.ok && /Invalid balance/.test(res.err), `رصيد غير صالح (${bad}) يُرفض`, res.err);
}
ok(JSON.stringify(await today()) === statsBefore && (await notes()).length === 0, '... ولا شيء انحفظ ولا تنبيه');

// تطابق المسارين: finish_kwtsms_send (بعد إرسال) والفحص اليومي — نفس الإشعار حرفياً، وتكرار مشترك
const hex = v => v.toString(16).padStart(64, '0'); let seq = 1;
const sendWithBalance = async bal => {
  const ev = hex(seq++), ph = hex(500000 + seq);
  const rs = await as('service_role', `select public.reserve_kwtsms_send(p_event => $1, p_phone => $2, p_test => false) r`, [ev, ph]);
  if (!rs.ok || rs.rows[0].r !== 'send') throw Error(`reserve: ${rs.err ?? rs.rows[0].r}`);
  const fin = await as('service_role', `select public.finish_kwtsms_send($1, 'accepted', 'm${seq}', 1, $2)`, [ev, bal]);
  if (!fin.ok) throw Error(fin.err);
};
const shape = rows => JSON.stringify(rows.map(x => [x.t, x.title, x.body, x.created_by, x.is_read]));
for (const bal of [40, 7]) {
  await db.exec(`delete from public.notifications`);
  await sendWithBalance(bal);
  const viaSend = await notes();
  await db.exec(`delete from public.notifications`);
  await check(bal);
  const viaCheck = await notes();
  ok(viaSend.length === 3 && shape(viaSend) === shape(viaCheck), `رصيد ${bal}: إشعار الفحص = إشعار ما بعد الإرسال حرفياً`);
}
await db.exec(`delete from public.notifications`);
await sendWithBalance(30);
ok((await check(25)).alerted === false && (await notes()).length === 3, 'تنبيه بعد إرسال يمنع تنبيه الفحص داخل الفاصل');
await db.exec(`delete from public.notifications`);
await check(25);
await sendWithBalance(20);
ok((await notes()).length === 3, 'وتنبيه الفحص يمنع تنبيه ما بعد الإرسال');
await sendWithBalance(9);
ok((await notes()).filter(x => x.title === URGENT).length === 3, 'وما بعد الإرسال ما زال يرسل «عاجل» كما هو');
await db.exec(`delete from public.notifications; delete from net.calls`);

// ── المهمة: نداء pg_net بالسرّ ──
ok(await as('postgres', `select 1`).then(x => x.ok), 'postgres (مالك المهمة) متاح');
let call = (await one(`select public.kwtsms_daily_balance_job() id`)).id;
ok(call === null && Number(await priv(`count(*)::int from net.calls`)) === 0, 'بلا سرّ محفوظ: لا نداء (ويرجع فارغاً بلا خطأ)');
await db.exec(`insert into private.app_secrets (key, value) values ('push_webhook_secret', 'synthetic-secret-48-chars-xxxxxxxxxxxxxxxxxxxxx')`);
call = (await one(`select public.kwtsms_daily_balance_job() id`)).id;
const c = await one(`select url, body, headers, timeout_ms from net.calls where id = $1`, [call]);
ok(c && c.url === 'https://poxyxsgvzwmnmewytsiw.supabase.co/functions/v1/kwtsms-cron', 'النداء: رابط kwtsms-cron الثابت', c?.url);
ok(JSON.stringify(c.body) === JSON.stringify({ action: 'balance_check' }), 'الجسم: {"action":"balance_check"}');
ok(c.headers['x-webhook-secret'] === 'synthetic-secret-48-chars-xxxxxxxxxxxxxxxxxxxxx' && c.headers['Content-Type'] === 'application/json'
  && Object.keys(c.headers).length === 2, 'الترويسة: x-webhook-secret (سرّ push_webhook_secret نفسه) فقط');
ok(c.timeout_ms === 20000, 'مهلة pg_net ٢٠ ثانية (أكبر من مهلتي KWT ٨ ث + التخزين ٣ ث)');
ok(Number(await priv(`count(*)::int from public.notifications`)) === 0, 'المهمة نفسها لا تنبّه ولا تحفظ (الدالة الطرفية تفعل)');

// ══════════ الميزة ٤: المحاولات المريبة ══════════
await db.exec(`delete from public.login_attempts; delete from public.notifications;`);
const sus = () => db.query(`select target_member_id t, title, body, created_by, is_read, details from public.notifications
  where kind = 'sms_suspicious' order by target_member_id`).then(x => x.rows);
const ageAttempts = (phone, mins) => db.query(`update public.login_attempts set created_at = created_at - make_interval(mins => $2) where phone = $1`, [phone, mins]);
const T = 'محاولات دخول مريبة';

for (let i = 0; i < 4; i++) ok((await log('96550001234', ['sent', 'blocked', 'failed', 'test'][i])).ok, `محاولة ${i + 1} تمر`);
ok((await sus()).length === 0, '٤ محاولات في ساعة: لا تنبيه');
ok((await log('96550001234', 'blocked')).ok, 'المحاولة ٥ تمر');
let s = await sus();
ok(s.length === 3, '٥ محاولات (أي نتيجة): تنبيه للمالك والمدراء المفعّلين', String(s.length));
const byT = t => s.find(x => x.t === t);
ok(byT(P.O)?.body === 'كاظم علي حسن المحمدعلي طلب رمز الدخول 5 مرات خلال ساعة — +965 50001234', 'المالك: الاسم والرقم كاملاً', byT(P.O)?.body);
ok(byT(P.A)?.body === 'كاظم علي حسن المحمدعلي طلب رمز الدخول 5 مرات خلال ساعة — +965 5000••34'
  && byT(P.A2)?.body === byT(P.A).body, 'المدير: الرقم مخفي «+965 5000••34»', byT(P.A)?.body);
ok(s.every(x => x.title === T && x.created_by === null && x.is_read === false && x.details === null), 'العنوان «محاولات دخول مريبة»، بلا مرسل ولا تفاصيل');
ok(!byT(P.FA) && !s.some(x => [P.M, P.MON, P.K].includes(x.t)), 'لا للمدير المجمّد ولا للمراقب ولا للعضو نفسه');
ok(s.filter(x => x.t !== P.O).every(x => !x.body.includes('50001234') && !x.body.includes('500012')), 'نص المدير بلا الرقم الكامل');
ok(Number(await priv(`count(*)::int from public.login_attempts where alerted`)) === 1
  && (await one(`select alerted from public.login_attempts order by id desc limit 1`)).alerted === true, 'المحاولة الخامسة معلَّمة alerted');
ok(Number(await priv(`count(*)::int from net.calls where url like 'https://push.test%'`)) === 3, 'كل إشعار مرّ بالدفع (مثل push-on-notification)');

for (let i = 0; i < 3; i++) await log('96550001234', 'blocked');
ok((await sus()).length === 3, 'المحاولات ٦–٨: لا تكرار');
await ageAttempts('96550001234', 11 * 60);
for (let i = 0; i < 5; i++) await log('96550001234', 'sent');
ok((await sus()).length === 3, 'بعد ١١ ساعة: ٥ جديدة في ساعة ولا تكرار (تنبيه خلال ١٢ ساعة)');
await ageAttempts('96550001234', 2 * 60);   // التنبيه الأول صار قبل ١٣ ساعة، والخمس الأخيرة قبل ساعتين
for (let i = 0; i < 4; i++) await log('96550001234', 'sent');
ok((await sus()).length === 3, 'بعد ١٣ ساعة: ٤ في الساعة الأخيرة ← لا (الأقدم خارج الستين دقيقة)');
await log('96550001234', 'sent');
s = await sus();
ok(s.length === 6 && s.filter(x => x.t === P.O).map(x => x.body).includes('كاظم علي حسن المحمدعلي طلب رمز الدخول 5 مرات خلال ساعة — +965 50001234'),
  '... والخامسة ← تنبيه جديد (مرة كل ١٢ ساعة)');

// العدد N الفعلي، رقم غير مسجّل، الاسم الأول عند فراغ الاسم الكامل، أرقام مستقلة
await db.exec(`delete from public.notifications`);
for (let i = 0; i < 4; i++) await log('96599990001', 'blocked');
await ageAttempts('96599990001', 61);
for (let i = 0; i < 4; i++) await log('96599990001', 'blocked');
ok((await sus()).length === 0, '٨ محاولات منها ٤ قبل ٦١ دقيقة: لا (النافذة ٦٠ دقيقة متحركة)');
await ageAttempts('96599990001', -2);   // تقريب الأربع القديمة لـ ٥٩ دقيقة
await log('96599990001', 'sent');
s = await sus();
ok(s.find(x => x.t === P.O)?.body === 'رقم غير مسجّل طلب رمز الدخول 9 مرات خلال ساعة — +965 99990001'
  && s.find(x => x.t === P.A)?.body === 'رقم غير مسجّل طلب رمز الدخول 9 مرات خلال ساعة — +965 9999••01',
  'رقم غير مسجّل: «رقم غير مسجّل» والعدد الفعلي ٩', s.map(x => x.body).join(' | '));
for (let i = 0; i < 5; i++) await log('96560002222', 'test');
s = await sus();
ok(s.filter(x => x.body.startsWith('نوح طلب رمز الدخول 5 مرات')).length === 3, 'رقم ثانٍ مستقل (والوضع التجريبي يُعدّ)؛ الاسم الأول عند فراغ الكامل');

// الخطأ لا يصعد: عطل pg_net (الدفع) أثناء التنبيه ← المحاولة محفوظة، التنبيه يتراجع ويُعاد لاحقاً
await db.exec(`delete from public.notifications; delete from public.login_attempts`);
for (let i = 0; i < 4; i++) await log('96550001234', 'sent');
await db.query(`select set_config('test.net_down', 'on', false)`);
res = await log('96550001234', 'sent');
ok(res.ok, 'عطل أثناء إدراج التنبيه: log_login_attempt تنجح بلا خطأ', res.err);
ok(Number(await priv(`count(*)::int from public.login_attempts where phone = '96550001234'`)) === 5
  && Number(await priv(`count(*)::int from public.login_attempts where alerted`)) === 0
  && (await sus()).length === 0, '... المحاولة محفوظة، والتنبيه وعلامته تراجعا معاً');
res = await log('96550001234', 'blocked');
ok(res.ok && (await sus()).length === 0, '... والعطل مستمر: ما زالت تنجح');
await db.query(`select set_config('test.net_down', '', false)`);
await log('96550001234', 'sent');
ok((await sus()).length === 3 && (await sus())[0].body.includes('7 مرات'), 'بعد زوال العطل: المحاولة التالية تنبّه (٧ مرات)');
// جدول إشعارات معطوب كلياً — لا يصعد أيضاً
await db.exec(`delete from public.notifications; delete from public.login_attempts; alter table public.notifications rename to notifications_x`);
for (let i = 0; i < 5; i++) res = await log('96550001234', 'sent');
ok(res.ok && Number(await priv(`count(*)::int from public.login_attempts`)) === 5, 'حتى بلا جدول إشعارات: المحاولات تُحفظ بلا خطأ');
await db.exec(`alter table public.notifications_x rename to notifications`);

// السلوك القائم: التحقق والحفظ المحدود والمطابقة كما هي
for (const [ph, oc] of [['+96550001234', 'sent'], ['96520001234', 'sent'], ['96550001234', 'accepted'], [null, 'sent'], ['96550001234', null]]) {
  res = await log(ph, oc);
  ok(!res.ok && res.code === '22023', `ما زال يرفض: ${ph} / ${oc}`, res.err);
}
ok((await one(`select profile_id from public.login_attempts where phone = '96550001234' order by id desc limit 1`)).profile_id === P.K,
  'المطابقة بالرقم كما هي');
await db.exec(`insert into public.login_attempts (phone, outcome, created_at)
  select '9655' || lpad(i::text, 7, '0'), 'sent', now() - interval '31 days' - (i || ' minutes')::interval from generate_series(1, 250) i;`);
await log('96560009999', 'sent');
ok(Number(await priv(`count(*)::int from public.login_attempts where created_at < now() - interval '30 days'`)) === 50, 'الحذف المحدود (٢٠٠ لكل تسجيل) كما هو');
res = await as('authenticated', `select public.log_login_attempt('96550001234', 'sent')`, [], 'owner');
ok(!res.ok && /permission denied/.test(res.err), 'log_login_attempt ما زالت ممنوعة على التطبيقات', res.err);

// ══════════ التراجع ══════════
await db.exec(RB);
ok(await md5('public.log_login_attempt(text,text)') === LIVE_LOG_MD5, 'التراجع: log_login_attempt = الحي حرفياً');
ok(await acl('public.log_login_attempt(text,text)') === LIVE_LOG_ACL, 'التراجع: نفس صلاحيات الحي');
ok(Number(await priv(`count(*)::int from pg_proc where proname in ('kwtsms_balance_check', 'kwtsms_daily_balance_job')`)) === 0, 'التراجع: الدالتان حُذفتا');
ok(Number(await priv(`count(*)::int from cron.job where jobname = 'kwtsms-daily-balance'`)) === 0, 'التراجع: المهمة أُلغيت');
ok(Number(await priv(`count(*)::int from information_schema.columns where table_name = 'login_attempts' and column_name = 'alerted'`)) === 0, 'التراجع: العمود حُذف');
for (const sig of KWT_FNS) ok(await md5(sig) === BEFORE[sig], `التراجع: ${sig.split('(')[0].slice(7)} كما كانت`);
await db.exec(`delete from public.notifications`);
for (let i = 0; i < 6; i++) res = await log('96550007777', 'sent');
ok(res.ok && (await sus()).length === 0, 'بعد التراجع: التسجيل يعمل بلا تنبيه (السلوك القديم)');
res = await db.exec(RB).then(() => ({ ok: true }), e => ({ ok: false, err: e.message }));
ok(res.ok, 'التراجع مرتين بلا خطأ', res.err);
await db.exec(MIG);
job = await one(`select count(*)::int n from cron.job where jobname = 'kwtsms-daily-balance'`);
ok(job.n === 1 && (await check(500)).state === 'ok', 'إعادة التطبيق بعد التراجع تعمل (مهمة واحدة)');
await db.exec(MIG.slice(MIG.indexOf('select cron.schedule')));
ok((await one(`select count(*)::int n from cron.job where jobname = 'kwtsms-daily-balance'`)).n === 1, 'تكرار الجدولة يحدّث ولا يكرر');

console.log(`\nالنتيجة: ${pass} نجحت، ${fail} فشلت`);
process.exit(fail ? 1 : 0);
