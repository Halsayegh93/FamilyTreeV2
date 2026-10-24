// تجربة 20261020170000 (حدود KWT SMS واسم المرسل يعدّلها المالك) على قاعدة محلية معزولة — لا تلمس السيرفر.
// ١) «قبل» = تعريفات الحي حرفياً (من ملف التراجع، md5 = pg_get_functiondef على الحي ٢٠٢٦-١٠-٢٠).
// ٢) بالقيم الافتراضية: نفس السيناريو قبل/بعد يعطي نفس النتائج حرفياً (الحجز بالرد القديم، اختبار المالك، الحفظ،
//    القراءتان) — والجديد فقط مفاتيح مضافة.
// ٣) القيم المعدّلة تنطبق، والصلاحيات (المالك فقط، المرسل من الخدمة فقط)، والقيود، ثم التراجع يعيد الحي حرفياً.
// التشغيل: cd supabase/tests/family_links && node kwtsms_editable_limits.test.mjs
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
process.on('unhandledRejection', e => { console.log('خطأ:', e.message, e.where ?? '', (e.query ?? '').slice(0, 300)); process.exit(2); });

const REPO = fileURLToPath(new URL('../../', import.meta.url));
const r = f => readFileSync(`${REPO}/${f}`, 'utf8');
const MIG = r('migrations/20261020170000_kwtsms_editable_limits.sql');
const RB = r('rollback/20261020170000_kwtsms_editable_limits_rollback.sql');
// تعريفات الحي (pg_get_functiondef، قراءة فقط ٢٠٢٦-١٠-٢٠)
const LIVE = {
  'public.reserve_kwtsms_send(text,text,boolean)': '131a68ec220bc9f7b8de5b7e69ef3c43',
  'public.reserve_kwtsms_admin_test(text,text,boolean)': 'c388a5e6e3314acd6f6e49922b0edfc2',
  'public.log_login_attempt(text,text)': '2e76aa4a600517fe024ba15191bcc6de',
  'public.sms_login_attempts(integer)': '7e55e62e16659c1f8189052354c72f39',
  'public.sms_admin_overview()': '01843bc975d451efb0eb62e3d6aac92a',
};

let pass = 0, fail = 0;
const ok = (c, m, x = '') => { c ? pass++ : fail++; console.log(`${c ? '✅' : '❌'} ${m}${!c && x !== '' ? ' — ' + x : ''}`); };
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const P = { O: id(1), A: id(2), M: id(3), K: id(10) };

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
  created_by uuid, title text, body text, kind text, is_read boolean default false, created_at timestamptz default now());
create or replace function public.current_user_role() returns text language sql stable as $$
  select nullif(current_setting('test.role', true), '') $$;
grant execute on function public.current_user_role() to anon, authenticated, service_role;
-- app_settings: سطر واحد بأعمدة + سياستا السيرفر الحي (القراءة للكل، التعديل للمالك) + صلاحيات الحي (كل شيء للتطبيقات)
create table public.app_settings (id uuid primary key default gen_random_uuid(),
  allow_new_registrations boolean not null default true, updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id));
insert into public.app_settings default values;
alter table public.app_settings enable row level security;
grant all on public.app_settings to anon, authenticated, service_role;
create policy "Authenticated users can read app_settings" on public.app_settings for select to authenticated using (true);
create policy "Owner can update app_settings" on public.app_settings for update to authenticated
  using (public.current_user_role() = 'owner') with check (public.current_user_role() = 'owner');
insert into public.profiles (id, role, status, phone_number, full_name, first_name) values
  ('${P.O}', 'owner', 'active', '+96590000001', 'المالك', 'مالك'),
  ('${P.A}', 'admin', 'active', '+96590000002', 'المدير', 'بدر'),
  ('${P.M}', 'member', 'active', '+96590000003', 'عضو', 'حسن'),
  ('${P.K}', 'member', 'active', '+96550001234', 'كاظم', 'كاظم');
insert into auth.users (id, phone) values ('${P.K}', '96550001234');
`);
for (const f of ['20261019200000_kwtsms_delivery_guard', '20261019210000_kwtsms_low_balance_alert', '20261019220000_kwtsms_cooldown_one_minute',
  '20261019230000_kwtsms_urgent_alert_12h', '20261020150000_kwtsms_daily_stats', '20261020151000_kwtsms_admin_overview',
  '20261020160000_login_attempts']) await db.exec(r(`migrations/${f}.sql`));
// الحي طُبّق بلا تعليقات رأس الملفات: «قبل» = نص الحي من ملف التراجع (يثبت أيضاً أن ملف التراجع = الحي حرفياً)
await db.exec(RB.slice(RB.indexOf('CREATE OR REPLACE FUNCTION public.reserve_kwtsms_send'), RB.indexOf('alter table public.app_settings')));
// صلاحيات Supabase الافتراضية (كما في الحي) — كل دالة جديدة تُمنح للتطبيقات، فيُثبت أن السحب يعمل
await db.exec(`alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;`);

const one = async (q, p = []) => (await db.query(q, p)).rows[0];
const md5 = async sig => (await one(`select md5(pg_get_functiondef('${sig}'::regprocedure)) m`)).m;
const acl = async sig => (await one(`select proacl::text a from pg_proc where oid = '${sig}'::regprocedure`)).a;
const throws = async (q, p = []) => { try { await db.query(q, p); return null; } catch (e) { return e; } };
for (const [sig, m] of Object.entries(LIVE)) ok(await md5(sig) === m, `قبل: ${sig.split('(')[0].slice(7)} = الحي حرفياً`);
const LIVE_ACL = {};
for (const sig of Object.keys(LIVE)) LIVE_ACL[sig] = await acl(sig);

// جلسة كتطبيق/خدمة: الدور + JWT
const as = async (who, role, sql, params = []) => {
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [JSON.stringify({ sub: who, role })]);
  await db.query(`select set_config('test.role', $1, false)`, [who === P.O ? 'owner' : who === P.A ? 'admin' : who ? 'member' : '']);
  await db.exec(`set role ${role}`);
  try { return { ok: true, rows: (await db.query(sql, params)).rows }; }
  catch (e) { return { ok: false, err: e.message, code: e.code, hint: e.hint }; }
  finally {
    await db.exec('reset role');
    await db.query(`select set_config('request.jwt.claims', '', false), set_config('test.role', '', false)`);
  }
};
const hex = n => n.toString(16).padStart(64, '0'); let seq = 1;
const reserve = async (ph, fmt) => fmt === undefined
  ? (await one(`select public.reserve_kwtsms_send(p_event => $1, p_phone => $2, p_test => false) r`, [hex(seq++), hex(ph)])).r
  : (await one(`select public.reserve_kwtsms_send(p_event => $1, p_phone => $2, p_test => false, p_format => $3) r`, [hex(seq++), hex(ph), fmt])).r;
const adminTest = async (ph, ev = hex(seq++)) => (await one(`select public.reserve_kwtsms_admin_test($1,$2,false) r`, [ev, hex(ph)])).r;
const age = s => db.exec(`update public.kwtsms_deliveries set created_at = created_at - interval '${s} seconds'`);
const fill = async (n, from = 2, step = 60) => {  // n إرسالات قديمة (أرقام مختلفة) متباعدة داخل الساعة
  for (let i = 0; i < n; i++) {
    await db.query(`insert into public.kwtsms_deliveries(event_hash, phone_hash, test_mode, created_at)
      values ($1, $2, false, clock_timestamp() - make_interval(secs => $3))`, [hex(900000 + seq++), hex(800000 + seq), from + i * step]);
  }
};
const clean = () => db.exec(`delete from public.kwtsms_deliveries; delete from public.login_attempts;`);
const log = (phone, outcome) => db.query(`select public.log_login_attempt($1, $2)`, [phone, outcome]);
const setRole = v => db.query(`select set_config('test.role', $1, false)`, [v]);
const overview = async () => { await setRole('owner'); const o = (await one(`select public.sms_admin_overview() o`)).o; await setRole(''); return o; };
const attempts = async (days, roleName = 'owner') => {
  await setRole(roleName);
  const o = (await one(days === undefined ? `select public.sms_login_attempts() j` : `select public.sms_login_attempts($1) j`,
    days === undefined ? [] : [days])).j;
  await setRole('');
  delete o.generated_at; return o;
};
const settings = () => one(`select sms_wait_seconds w, sms_per_number_hour n, sms_all_hour h, login_attempts_retention_days d,
  sms_sender s, updated_by from public.app_settings`);

// ── سيناريو ثابت يُشغَّل قبل وبعد (بالرد القديم) ──
async function scenario() {
  const out = [];
  out.push(await reserve(1));                                  // send
  await age(30); out.push(await reserve(1));                   // blocked (مهلة الرقم)
  await age(19); out.push(await reserve(1));                   // ٤٩ ث: blocked
  await age(6); out.push(await reserve(1));                    // ٥٥ ث: send
  for (let i = 0; i < 3; i++) { await age(55); out.push(await reserve(1)); }   // send ×٣ (٥ بالساعة)
  await age(55); out.push(await reserve(1));                   // blocked (٥ بالساعة للرقم)
  out.push(await reserve(2));                                  // رقم ثاني: send
  for (let p = 3; p <= 6; p++) out.push(await reserve(p));     // ٥ في الثانية (مع رقم ٢)
  out.push(await reserve(7));                                  // blocked (٥ بالثانية)
  await age(2); out.push(await reserve(7));                    // send
  await fill(90, 3, 30);                                       // الكل بالساعة: ٩٠ + ١١ = ١٠١ ≥ ١٠٠
  await age(2); out.push(await reserve(8));                    // blocked (١٠٠ بالساعة)
  // حدث مكرر: مقبول ← accepted، معلّق ← blocked (بلا أي حد آخر: لولا التكرار لكان send)
  await clean();
  const ev = hex(seq++), ev2 = hex(seq++);
  await db.query(`insert into public.kwtsms_deliveries(event_hash, phone_hash, test_mode, outcome, created_at)
    values ($1, $2, false, 'accepted', clock_timestamp() - interval '5 minutes'),
           ($3, $2, false, 'pending', clock_timestamp() - interval '6 minutes')`, [ev, hex(9), ev2]);
  out.push((await one(`select public.reserve_kwtsms_send($1,$2,false) r`, [ev, hex(12)])).r);
  out.push((await one(`select public.reserve_kwtsms_send($1,$2,false) r`, [ev2, hex(12)])).r);
  // الحذف بعد يومين
  await clean();
  await db.query(`insert into public.kwtsms_deliveries(event_hash, phone_hash, test_mode, created_at)
    values ($1, $2, false, clock_timestamp() - interval '2 days 1 minute')`, [hex(700000 + seq++), hex(10)]);
  out.push(await reserve(10));
  out.push(Number((await one(`select count(*)::int n from public.kwtsms_deliveries where phone_hash = $1`, [hex(10)])).n));
  // اختبار المالك
  await clean();
  out.push(await adminTest(20));                               // send
  out.push(await adminTest(21));                               // wait (١٠ دقائق)
  await db.exec(`update public.kwtsms_deliveries set created_at = created_at - interval '11 minutes'`);
  await reserve(22); out.push(await adminTest(22));            // blocked (مهلة الرقم)
  await age(51); out.push(await adminTest(22));                // send
  await db.exec(`update public.kwtsms_deliveries set created_at = created_at - interval '11 minutes'`);
  await fill(100, 2, 30); out.push(await adminTest(23));       // blocked (١٠٠ بالساعة)
  // الحفظ: ٣١ يوماً تُحذف، ٢٩ تبقى
  await clean();
  await log('96550001234', 'sent');
  await db.exec(`update public.login_attempts set created_at = now() - interval '31 days'`);
  await log('96550001234', 'blocked');
  await db.exec(`update public.login_attempts set created_at = now() - interval '29 days' where outcome = 'blocked'`);
  await log('96550001234', 'sent');
  out.push((await db.query(`select outcome from public.login_attempts order by id`)).rows.map(x => x.outcome).join(','));
  for (const d of [undefined, 1, 7, 29, 30, 31, 0, -5, null]) {
    const o = await attempts(d); out.push(JSON.stringify([o.days, o.retention_days, o.totals]));
  }
  out.push(JSON.stringify(await attempts(30, 'admin')).replace(/"last_at":"[^"]*"|"first_at":"[^"]*"/g, ''));
  await clean();
  return out;
}
const BEFORE = await scenario();
// بيانات ثابتة للقراءتين (نفس البيانات قبل الترحيل وبعده)
await reserve(30); await age(5); await reserve(31); await fill(12, 120, 60);
await db.exec(`update public.kwtsms_deliveries set outcome = 'accepted', balance_after = 77, points_charged = 1 where phone_hash = '${hex(30)}'`);
await log('96550001234', 'sent'); await log('96599990001', 'blocked');
const O1 = await overview(); const S1 = await attempts(7); const S1a = await attempts(30, 'admin');

// ══ الترحيل ══
await db.exec(MIG);
ok(Number((await one(`select count(*)::int n from pg_proc where proname = 'reserve_kwtsms_send'`)).n) === 1,
  'reserve_kwtsms_send نسخة واحدة (لا تعارض في PostgREST)');
const RES4 = 'public.reserve_kwtsms_send(text,text,boolean,integer)';
ok(await acl(RES4) === LIVE_ACL['public.reserve_kwtsms_send(text,text,boolean)'], 'الحجز: نفس صلاحيات الحي (الخدمة فقط)', await acl(RES4));
for (const sig of Object.keys(LIVE).filter(s => !s.startsWith('public.reserve_kwtsms_send'))) {
  ok(await acl(sig) === LIVE_ACL[sig], `${sig.split('(')[0].slice(7)}: الصلاحيات كما هي`);
}
ok(await acl('public.set_kwtsms_sender(text,uuid)') === '{postgres=X/postgres,service_role=X/postgres}', 'set_kwtsms_sender: للخدمة فقط',
  await acl('public.set_kwtsms_sender(text,uuid)'));

// ── القراءتان على نفس البيانات: نفس الرد + المفاتيح الجديدة فقط ──
const O2 = await overview(); const S2 = await attempts(7); const S2a = await attempts(30, 'admin');
const strip = o => { const c = structuredClone(o); delete c.sender; delete c.retention; delete c.limits.wait_seconds; return c; };
ok(JSON.stringify(strip(O2)) === JSON.stringify(O1), 'النظرة العامة بالافتراضي = الحي حرفياً (عدا المفاتيح المضافة)',
  JSON.stringify(strip(O2)).slice(0, 200));
ok(O2.limits.wait_seconds === 60 && O2.limits.phone_cooldown_seconds === 50 && O2.limits.phone_per_hour === 5
  && O2.limits.all_per_hour === 100 && O2.hour.cap === 100, 'الحدود الافتراضية: انتظار ٦٠ (مهلة داخلية ٥٠)، ٥ للرقم، ١٠٠ للكل');
ok(JSON.stringify(O2.retention) === '{"deliveries_days":2,"login_attempts_days":30}' && O2.retention_days === 2, 'الحفظ: الإرسالات يومان، المحاولات ٣٠ يوماً');
ok(JSON.stringify(O2.sender) === '{"source":"default","current":"KWT-SMS","default":"KWT-SMS"}', 'المرسل: الافتراضي', JSON.stringify(O2.sender));
ok(JSON.stringify(S2) === JSON.stringify(S1) && JSON.stringify(S2a) === JSON.stringify(S1a), 'محاولات الدخول بالافتراضي = الحي حرفياً');
await clean();

// ── نفس السيناريو بالرد القديم (الدالة الطرفية المنشورة v20) ──
const AFTER = await scenario();
ok(JSON.stringify(AFTER) === JSON.stringify(BEFORE), 'السيناريو بالافتراضي = الحي حرفياً (٥٠ ث، ٥/ساعة، ٥/ثانية، ١٠٠/ساعة، يومان، ١٠ دقائق، ٣٠ يوماً)',
  JSON.stringify(AFTER.map((v, i) => v === BEFORE[i] ? '=' : [v, BEFORE[i]])));
ok(BEFORE.slice(0, 8).join() === 'send,blocked,blocked,send,send,send,send,blocked'
  && BEFORE.slice(8, 20).join() === 'send,send,send,send,send,blocked,send,blocked,accepted,blocked,send,1'
  && BEFORE.slice(20, 25).join() === 'send,wait,blocked,send,blocked' && BEFORE[25] === 'blocked,sent',
  'السيناريو نفسه يغطي كل الحدود (مهلة، ٥/ساعة، ٥/ثانية، ١٠٠/ساعة، التكرار، اليومان، اختبار المالك، الحفظ)', BEFORE.slice(0, 26).join());
// الرد المفصّل لحدث مكرر معلّق = «blocked» بلا ثوانٍ (الدالة الطرفية ترد بالرسالة القديمة)
{
  const evp = hex(seq++);
  await db.query(`insert into public.kwtsms_deliveries(event_hash, phone_hash, test_mode, created_at)
    values ($1, $2, false, clock_timestamp() - interval '6 minutes')`, [evp, hex(13)]);
  ok((await one(`select public.reserve_kwtsms_send($1,$2,false,2) r`, [evp, hex(14)])).r === 'blocked', 'مفصّل: حدث مكرر معلّق ← «blocked»');
  await clean();
}

// ── الرد المفصّل (p_format 2) ──
ok(await reserve(40, 2) === 'send', 'مفصّل: بلا مرسل محفوظ ← «send» (الدالة الطرفية تستخدم الافتراضي)');
await age(30);
let b = await reserve(40, 2);
ok(/^blocked:(29|30|31)$/.test(b), 'مفصّل: بعد ٣٠ ث ← «blocked:30» (٦٠ - ٣٠)', b);
ok(await reserve(40) === 'blocked' && await reserve(40, 1) === 'blocked' && await reserve(40, null) === 'blocked', 'القديم/١/null ← «blocked» حرفياً');
await age(25); ok(await reserve(40, 2) === 'send', 'مفصّل: بعد ٥٥ ث ← send (المهلة الداخلية ٥٠)');
await clean();
for (let p = 50; p < 55; p++) await reserve(p, 2);
b = await reserve(55, 2); ok(b === 'blocked:1', 'مفصّل: ٥ بالثانية ← «blocked:1»', b);
await clean(); await fill(100, 2, 30);   // أقدم المئة عمرها ٢٩٧٢ ث ← يفرج بعد ٦٢٨
b = await reserve(56, 2); ok(/^blocked:(627|628|629)$/.test(b), 'مفصّل: ١٠٠ بالساعة ← حتى يطلع أقدمها من الساعة (~٦٢٨ ث)', b);
await clean();

// ── الصلاحيات: المالك فقط يعدّل، والقيود ──
let res = await as(P.A, 'authenticated', `update public.app_settings set sms_wait_seconds = 120, sms_per_number_hour = 2, sms_all_hour = 20,
  login_attempts_retention_days = 7 returning 1`);
let s = await settings();
ok(res.ok && res.rows.length === 0 && s.w === 60 && s.n === 5 && s.h === 100 && s.d === 30, 'المدير: لا يعدّل (٠ صفوف، القيم كما هي)', JSON.stringify(res));
res = await as(P.M, 'authenticated', `update public.app_settings set sms_wait_seconds = 120 returning 1`);
ok(res.ok && res.rows.length === 0 && (await settings()).w === 60, 'العضو: لا يعدّل');
res = await as(null, 'anon', `update public.app_settings set sms_wait_seconds = 120 returning 1`);
ok(res.ok && res.rows.length === 0 && (await settings()).w === 60, 'الزائر: لا يعدّل');
res = await as(P.A, 'authenticated', `select sms_wait_seconds, sms_sender from public.app_settings`);
ok(res.ok && res.rows[0].sms_wait_seconds === 60, 'المدير يقرأ الإعدادات');
for (const [col, v] of [['sms_wait_seconds', 59], ['sms_wait_seconds', 601], ['sms_wait_seconds', 30], ['sms_per_number_hour', 0],
  ['sms_per_number_hour', 21], ['sms_all_hour', 19], ['sms_all_hour', 1001], ['login_attempts_retention_days', 6],
  ['login_attempts_retention_days', 91], ['sms_wait_seconds', null]]) {
  res = await as(P.O, 'authenticated', `update public.app_settings set ${col} = ${v} returning 1`);
  ok(!res.ok && ['23514', '23502'].includes(res.code), `القيد يرفض ${col} = ${v}`, JSON.stringify(res));
}
res = await as(P.O, 'authenticated', `update public.app_settings set sms_wait_seconds = 120, sms_per_number_hour = 2, sms_all_hour = 20,
  login_attempts_retention_days = 7, updated_by = '${P.O}' returning 1`);
s = await settings();
ok(res.ok && res.rows.length === 1 && s.w === 120 && s.n === 2 && s.h === 20 && s.d === 7, 'المالك يعدّل الأربعة', JSON.stringify(res));

// ── القيم المعدّلة تنطبق ──
// الانتظار ١٢٠: الثاني عند ٧٠ ث ممنوع والباقي ~٥٠؛ عند ١٠٥ ث ~١٥؛ عند ١١١ ث (المهلة الداخلية ١١٠) يمر
ok(await reserve(60, 2) === 'send', 'انتظار ١٢٠: الأول');
await age(70); b = await reserve(60, 2);
ok(/^blocked:(49|50|51)$/.test(b), 'انتظار ١٢٠: عند ٧٠ ث ← «blocked:50»', b);
ok(await reserve(60) === 'blocked', 'انتظار ١٢٠: بالرد القديم ← «blocked» (الدالة الطرفية v20 تحترم الحد الجديد)');
await age(35); b = await reserve(60, 2); ok(/^blocked:(14|15|16)$/.test(b), 'انتظار ١٢٠: عند ١٠٥ ث ← «blocked:15»', b);
await age(6); ok(await reserve(60, 2) === 'send', 'انتظار ١٢٠: عند ١١١ ث يمر');
// ٢ للرقم بالساعة: الثالث ممنوع حتى يطلع الأول من الساعة
await age(130); b = await reserve(60, 2);
ok(/^blocked:(3358|3359|3360)$/.test(b), 'رقمين بالساعة: الثالث ممنوع (~٣٣٥٩ ث حتى يطلع الأول)', b);
ok(await reserve(61, 2) === 'send', 'رقم آخر ما يتأثر');
await clean();
// ٢٠ للكل بالساعة
await fill(19, 2, 60); ok(await reserve(62, 2) === 'send', '٢٠ للكل: رقم ٢٠ يمر');
await age(2); b = await reserve(63, 2);
ok(/^blocked:(2515|2516|2517)$/.test(b), '٢٠ للكل: رقم ٢١ ممنوع حتى يطلع أقدمها (~٢٥١٦ ث)', b);
ok(await adminTest(64) === 'blocked', '٢٠ للكل: «اختبار إرسال لرقمي» يحترمها');
await clean();
// «اختبار إرسال لرقمي» يحترم الانتظار المعدّل
await reserve(65); await age(100); ok(await adminTest(65) === 'blocked', 'اختبار المالك: مهلة الرقم ١١٠ ث (عند ١٠٠ ممنوع)');
await age(11); ok(await adminTest(65) === 'send', 'اختبار المالك: عند ١١١ ث يمر');
await clean();
// الحفظ ٧ أيام
await log('96550001234', 'sent');
await db.exec(`update public.login_attempts set created_at = now() - interval '8 days'`);
await log('96550001234', 'blocked');
await db.exec(`update public.login_attempts set created_at = now() - interval '6 days' where outcome = 'blocked'`);
await log('96550001234', 'sent');
ok((await db.query(`select outcome from public.login_attempts order by id`)).rows.map(x => x.outcome).join() === 'blocked,sent',
  'حفظ ٧ أيام: محاولة ٨ أيام انحذفت و٦ أيام باقية');
let a = await attempts(30);
ok(a.days === 7 && a.retention_days === 7 && a.totals.attempts === 2, 'القراءة: سقف الفترة = ٧ والحفظ ٧', JSON.stringify([a.days, a.retention_days, a.totals]));
a = await attempts(3); ok(a.days === 3, 'القراءة: أقل من الحفظ كما هو');
let o = await overview();
ok(o.limits.wait_seconds === 120 && o.limits.phone_cooldown_seconds === 110 && o.limits.phone_per_hour === 2
  && o.limits.all_per_hour === 20 && o.hour.cap === 20 && o.retention.login_attempts_days === 7 && o.limits.all_per_second === 5
  && o.limits.admin_test_minutes === 10, 'النظرة العامة تعكس الإعدادات', JSON.stringify([o.limits, o.hour, o.retention]));
// أقصى الحدود
res = await as(P.O, 'authenticated', `update public.app_settings set sms_wait_seconds = 600, sms_per_number_hour = 20, sms_all_hour = 1000,
  login_attempts_retention_days = 90 returning 1`);
ok(res.ok && res.rows.length === 1, 'المالك: أقصى القيم مقبولة (٦٠٠، ٢٠، ١٠٠٠، ٩٠)');
ok((await attempts(120)).days === 90, 'حفظ ٩٠: سقف القراءة ٩٠');
await clean();
await reserve(66); await age(589); b = await reserve(66, 2);
ok(/^blocked:(10|11|12)$/.test(b), 'انتظار ٦٠٠: عند ٥٨٩ ث ممنوع (~١١)', b);
await age(2); ok(await reserve(66, 2) === 'send', 'انتظار ٦٠٠: عند ٥٩١ ث (المهلة الداخلية ٥٩٠) يمر');
await clean();

// ── بلا سطر إعدادات: الثوابت السابقة ──
const saved = await one(`select * from public.app_settings`);
await db.exec(`alter table public.app_settings disable trigger trg_app_settings_sms_sender_guard; delete from public.app_settings;`);
ok(await reserve(70, 2) === 'send', 'بلا إعدادات: يعمل');
await age(30); b = await reserve(70, 2); ok(/^blocked:(29|30|31)$/.test(b), 'بلا إعدادات: انتظار ٦٠ الافتراضي', b);
await age(21); ok(await reserve(70, 2) === 'send', 'بلا إعدادات: المهلة الداخلية ٥٠');
await log('96550001234', 'sent');
o = await overview();
ok(o.limits.wait_seconds === 60 && o.hour.cap === 100 && o.retention.login_attempts_days === 30 && o.sender.source === 'default'
  && (await attempts(40)).days === 30, 'بلا إعدادات: النظرة والقراءة بالثوابت');
await db.query(`insert into public.app_settings (id, updated_at) values ($1, $2)`, [saved.id, saved.updated_at]);
await db.exec(`alter table public.app_settings enable trigger trg_app_settings_sms_sender_guard;
  update public.app_settings set sms_wait_seconds = 60, sms_per_number_hour = 5, sms_all_hour = 100, login_attempts_retention_days = 30;`);
await clean();

// ── اسم المرسل: الخدمة فقط ──
res = await as(P.O, 'authenticated', `update public.app_settings set sms_sender = 'MYAPP' returning 1`);
ok(!res.ok && res.code === '42501' && res.hint === 'sms_sender_service_only', 'المالك: لا يكتب المرسل مباشرة (42501)', JSON.stringify(res));
res = await as(P.O, 'authenticated', `update public.app_settings set sms_wait_seconds = 90, sms_sender = null returning 1`);
ok(res.ok && res.rows.length === 1 && (await settings()).w === 90, 'المالك: المرسل غير المتغيّر (null = null) لا يمنع تعديل الباقي');
res = await as(P.O, 'authenticated', `select public.set_kwtsms_sender('MYAPP', '${P.O}')`);
ok(!res.ok && /permission denied/.test(res.err), 'المالك: لا يستدعي set_kwtsms_sender (للخدمة فقط)', res.err);
res = await as(null, 'anon', `select public.set_kwtsms_sender('MYAPP')`);
ok(!res.ok && /permission denied/.test(res.err), 'الزائر: لا يستدعيها');
res = await as(null, 'service_role', `select public.set_kwtsms_sender('MYAPP', '${P.O}') v`);
s = await settings();
ok(res.ok && res.rows[0].v === 'MYAPP' && s.s === 'MYAPP' && s.updated_by === P.O, 'الخدمة: تحفظ المرسل (ومن عدّل)', JSON.stringify(res));
ok(await reserve(80, 2) === 'send:MYAPP', 'الحجز المفصّل يرجع المرسل المحفوظ');
ok(await reserve(81) === 'send' && await reserve(82, 1) === 'send', 'الرد القديم «send» حرفياً حتى مع مرسل محفوظ');
o = await overview();
ok(JSON.stringify(o.sender) === '{"source":"settings","current":"MYAPP","default":"KWT-SMS"}', 'النظرة: المرسل من الإعدادات', JSON.stringify(o.sender));
res = await as(P.O, 'authenticated', `update public.app_settings set sms_sender = null returning 1`);
ok(!res.ok && res.hint === 'sms_sender_service_only' && (await settings()).s === 'MYAPP', 'المالك: لا يمسح المرسل مباشرة');
res = await as(P.O, 'authenticated', `update public.app_settings set sms_wait_seconds = 60 returning 1`);
ok(res.ok && res.rows.length === 1 && (await settings()).s === 'MYAPP', 'المالك يعدّل غيره والمرسل المحفوظ باقٍ');
// دالة SECURITY DEFINER يستدعيها مستخدم (JWT authenticated) لا تقدر تغيّره
await db.exec(`create function public.tmp_definer_set_sender(v text) returns void language sql security definer set search_path = ''
  as $$ update public.app_settings set sms_sender = v $$; grant execute on function public.tmp_definer_set_sender(text) to authenticated;`);
res = await as(P.O, 'authenticated', `select public.tmp_definer_set_sender('EVIL')`);
ok(!res.ok && res.hint === 'sms_sender_service_only' && (await settings()).s === 'MYAPP', 'دالة SECURITY DEFINER بجلسة مستخدم: مرفوض', JSON.stringify(res));
await db.exec(`drop function public.tmp_definer_set_sender(text)`);
res = await as(null, 'service_role', `update public.app_settings set sms_sender = 'KWT-SMS' returning 1`);
ok(res.ok && (await settings()).s === 'KWT-SMS', 'الخدمة مباشرة (مفتاح الخدمة): مسموح');
await db.exec(`update public.app_settings set sms_sender = 'MAINT'`);
ok((await settings()).s === 'MAINT', 'صيانة SQL بلا مستخدم: مسموحة');
for (const bad of ['BAD!', 'TWELVECHARSX', '', 'عربي', 'A\nB']) {
  const e1 = await throws(`update public.app_settings set sms_sender = $1`, [bad]);
  res = await as(null, 'service_role', `select public.set_kwtsms_sender($1)`, [bad]);
  ok(e1?.code === '23514' && !res.ok && res.code === '22023', `صيغة مرفوضة: ${JSON.stringify(bad)} (القيد + الدالة)`, JSON.stringify([e1?.code, res]));
}
await db.exec(`update public.app_settings set sms_sender = 'MY APP-1'`);
ok(await reserve(83, 2) === 'send:MY APP-1', 'مسافة وشرطة مسموحتان');
res = await as(null, 'service_role', `select public.set_kwtsms_sender(null, '${P.NOBODY ?? id(99)}') v`);
s = await settings();
ok(res.ok && res.rows[0].v === null && s.s === null && s.updated_by === P.O, 'الخدمة: null يرجع للافتراضي (ومعرّف غير موجود لا يكسر updated_by)', JSON.stringify([res, s]));
ok(await reserve(84, 2) === 'send' && (await overview()).sender.source === 'default', 'بعد الرجوع: «send» والمصدر «default»');
await clean();

// ══ التراجع ══
await db.exec(`update public.app_settings set sms_wait_seconds = 120`);
await db.exec(RB);
for (const [sig, m] of Object.entries(LIVE)) ok(await md5(sig) === m, `التراجع: ${sig.split('(')[0].slice(7)} = الحي حرفياً`);
for (const sig of Object.keys(LIVE)) ok(await acl(sig) === LIVE_ACL[sig], `التراجع: صلاحيات ${sig.split('(')[0].slice(7)} كما في الحي`, await acl(sig));
ok(Number((await one(`select count(*)::int n from pg_proc where proname in ('reserve_kwtsms_send','set_kwtsms_sender','app_settings_sms_sender_guard')`)).n) === 1
  && Number((await one(`select count(*)::int n from pg_trigger where tgname = 'trg_app_settings_sms_sender_guard'`)).n) === 0,
  'التراجع: الحارس ودالة المرسل محذوفة، والحجز نسخة واحدة');
ok(Number((await one(`select count(*)::int n from information_schema.columns where table_name = 'app_settings'
  and column_name in ('sms_wait_seconds','sms_per_number_hour','sms_all_hour','login_attempts_retention_days','sms_sender')`)).n) === 0,
  'التراجع: الأعمدة الخمسة محذوفة');
const ROLLED = await scenario();
ok(JSON.stringify(ROLLED) === JSON.stringify(BEFORE), 'التراجع: السيناريو = الحي حرفياً');
// إعادة التطبيق بعد التراجع تعمل
await db.exec(MIG);
ok(await reserve(90, 2) === 'send', 'إعادة التطبيق بعد التراجع تعمل');

console.log(`\n${pass} نجح، ${fail} فشل`); process.exit(fail ? 1 : 0);
