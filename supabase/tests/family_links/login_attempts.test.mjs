// تجربة 20261020160000 («محاولات الدخول») على قاعدة محلية معزولة — لا تلمس السيرفر.
// القاعدة = base.sql + حماية روابط العائلة (١ أكتوبر) + ترحيلات KWT SMS الست (المطبّقة على الحي)،
// مع صلاحيات Supabase الافتراضية (كل جدول/دالة/تسلسل جديد يُمنح للتطبيقات) حتى يُثبت أن السحب يعمل.
// كل قراءة بدور authenticated وJWT المتصل؛ auth.users بلا أي صلاحية للتطبيقات.
// التشغيل: cd supabase/tests/family_links && node login_attempts.test.mjs
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
process.on('unhandledRejection', e => { console.log('خطأ:', e.message, e.where ?? '', (e.query ?? '').slice(0, 300)); process.exit(2); });

const REPO = fileURLToPath(new URL('../../', import.meta.url));
const r = f => readFileSync(`${REPO}/${f}`, 'utf8');
const base = readFileSync(new URL('./base.sql', import.meta.url), 'utf8');
const [baseBody, rest] = base.split('-- ─── المشغّلات');
const baseTriggers = rest.slice(rest.indexOf('\n') + 1);
const grab = (src, name) => { const i = src.indexOf(`create or replace function public.${name}(`); return src.slice(i, src.indexOf('$function$;', i) + '$function$;'.length); };
const preFns = ['adopt_tree_profile', 'merge_member_into_tree', 'women_auto_merge_wife']
  .map(n => grab(r('rollback/20261001150000_protect_family_links_rollback.sql'), n)).join('\n\n');
const MIG = r('migrations/20261020160000_login_attempts.sql');
const RB = r('rollback/20261020160000_login_attempts_rollback.sql');
// دوال KWT الموجودة — يجب ألا يغيّرها الترحيل ولا تراجعه (الحي طُبّق بلا تعليقات فبصمته تختلف عن الملفات حرفياً؛
// المقارنة هنا قبل/بعد على نفس القاعدة)
const KWT_FNS = ['public.reserve_kwtsms_send(text,text,boolean)', 'public.finish_kwtsms_send(text,text,text,numeric,numeric,text)',
  'public.sms_admin_overview()', 'public.sms_balance_status()'];

let pass = 0, fail = 0;
const ok = (c, m, x = '') => { c ? pass++ : fail++; console.log(`${c ? '✅' : '❌'} ${m}${!c && x ? ' — ' + x : ''}`); };
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const P = { O: id(1), A: id(2), M: id(3), MON: id(4), SUP: id(5), FA: id(6), PEND: id(7), K: id(10), X: id(11), XAUTH: id(12),
  L: id(13), M2: id(14), D: id(15), NOBODY: id(99) };

const db = new PGlite();
await db.exec(baseBody); await db.exec(preFns); await db.exec(baseTriggers);
for (const f of ['20261001150000_protect_family_links', '20261001190000_carry_own_women_node_links']) await db.exec(r(`migrations/${f}.sql`));
// app_settings كما في تجربة kwtsms_admin_stats (سطر واحد) — تحتاجه ترحيلات KWT
await db.exec(`create table public.app_settings (id uuid primary key default gen_random_uuid(),
  allow_new_registrations boolean not null default true, updated_at timestamptz not null default now(), updated_by uuid);
insert into public.app_settings default values;
alter table auth.users add column last_sign_in_at timestamptz;`);
for (const f of ['20261019200000_kwtsms_delivery_guard', '20261019210000_kwtsms_low_balance_alert', '20261019220000_kwtsms_cooldown_one_minute',
  '20261019230000_kwtsms_urgent_alert_12h', '20261020150000_kwtsms_daily_stats', '20261020151000_kwtsms_admin_overview']) await db.exec(r(`migrations/${f}.sql`));

const one = async (q, p = []) => (await db.query(q, p)).rows[0];
const md5 = async sig => (await one(`select md5(pg_get_functiondef('${sig}'::regprocedure)) m`)).m;
const BEFORE = {}; for (const sig of KWT_FNS) BEFORE[sig] = await md5(sig);

// صلاحيات Supabase الافتراضية (كما في الحي: pg_default_acl لـ postgres في public)
await db.exec(`alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;`);

// ── الأعضاء والحسابات ──
await db.exec(`
insert into public.profiles (id, first_name, full_name, gender, role, status, phone_number, created_at) values
  ('${P.O}',   'مالك',  'المالك',               'male', 'owner',      'active',  '+96590000001', now() - interval '900 days'),
  ('${P.A}',   'بدر',   'المدير',               'male', 'admin',      'active',  '+96590000002', now() - interval '800 days'),
  ('${P.M}',   'حسن',   'عضو عادي',             'male', 'member',     'active',  '+96590000003', now() - interval '700 days'),
  ('${P.MON}', 'مراقب', 'المراقب',              'male', 'monitor',    'active',  '+96590000004', now() - interval '700 days'),
  ('${P.SUP}', 'مشرف',  'المشرف',               'male', 'supervisor', 'active',  '+96590000005', now() - interval '700 days'),
  ('${P.FA}',  'مجمد',  'مدير مجمّد',           'male', 'admin',      'frozen',  '+96590000006', now() - interval '700 days'),
  ('${P.PEND}','جديد',  'مسجّل معلّق',          'male', 'pending',    'pending', '+96590000007', now() - interval '1 day'),
  ('${P.K}',   'كاظم',  'كاظم علي حسن المحمدعلي','male', 'member',     'active',  '+96550001234', now() - interval '600 days'),
  ('${P.X}',   'ياسر',  'ياسر ملف منقول',       'male', 'member',     'active',  null,           now() - interval '600 days'),
  ('${P.L}',   'ليث',   'ليث رقم قديم',          'male', 'member',     'active',  '60001111',     now() - interval '600 days'),
  ('${P.M2}',  'مهدي',  'مهدي دخل قديماً',       'male', 'member',     'active',  '+96551112222', now() - interval '600 days'),
  ('${P.D}',   'دانة',  'عضو سيُحذف',            'male', 'member',     'active',  '+96566600000', now() - interval '600 days');
-- حسابات الدخول (auth.users) — XAUTH حساب منقول: app_metadata.profile_id = X
insert into auth.users (id, phone, raw_app_meta_data, last_sign_in_at) values
  ('${P.O}', '96590000001', '{}', now()), ('${P.A}', '96590000002', '{}', now()), ('${P.M}', '96590000003', '{}', now()),
  ('${P.MON}', '96590000004', '{}', now()), ('${P.SUP}', '96590000005', '{}', now()), ('${P.FA}', '96590000006', '{}', now()),
  ('${P.PEND}', '96590000007', '{}', now()),
  ('${P.K}', '96550001234', '{}', null),
  ('${P.XAUTH}', '96555500000', '{"profile_id": "${P.X}"}', now() - interval '20 days'),
  ('${P.M2}', '96551112222', '{}', null);`);

const as = async (who, sql, params = [], dbRole = 'authenticated') => {
  if (who) await db.query(`select set_config('request.jwt.claims', $1, false)`, [JSON.stringify({ sub: who, role: dbRole })]);
  await db.exec(`set role ${dbRole}`);
  try { return { ok: true, rows: (await db.query(sql, params)).rows }; }
  catch (e) { return { ok: false, err: e.message, code: e.code }; }
  finally { await db.exec('reset role'); await db.query(`select set_config('request.jwt.claims', '', false)`); }
};
// الدالة الطرفية = service_role
const log = (phone, outcome) => as(null, `select public.log_login_attempt($1, $2)`, [phone, outcome], 'service_role');
const M0 = (await one(`select (((now() at time zone 'Asia/Kuwait')::date)::timestamp at time zone 'Asia/Kuwait')::text t`)).t;
const at = off => `'${M0}'::timestamptz + interval '${off}'`;
// يسجّل عبر الدالة ثم يضبط وقته (كأنه حصل في وقت سابق)
const logAt = async (phone, outcome, off) => {
  const res = await log(phone, outcome);
  if (!res.ok) throw Error(`log ${phone} ${outcome}: ${res.err}`);
  await db.exec(`update public.login_attempts set created_at = ${at(off)} where id = (select max(id) from public.login_attempts)`);
};
const read = async (who, days) => {
  const res = await as(who, days === undefined ? `select public.sms_login_attempts() j` : `select public.sms_login_attempts($1) j`,
    days === undefined ? [] : [days]);
  return res.ok ? res.rows[0].j : res;
};
const item = (o, e164tail) => o.items.find(x => (x.phone_e164 ?? '').endsWith(e164tail) || x.phone.replace(/\s/g, '').endsWith(e164tail));

// ── الترحيل ──
await db.exec(MIG);
for (const sig of KWT_FNS) ok(await md5(sig) === BEFORE[sig], `بعد: ${sig.split('(')[0]} ما تغيّرت`);

// ── الصلاحيات ──
const priv = async (q) => (await one(`select (select ${q}) x`)).x;
ok(await priv(`relrowsecurity from pg_class where oid = 'public.login_attempts'::regclass`)
  && Number(await priv(`count(*)::int from pg_policies where tablename = 'login_attempts'`)) === 0, 'الجدول: RLS مفعّل بلا أي سياسة');
for (const who of ['anon', 'authenticated']) {
  ok(!(await priv(`has_table_privilege('${who}', 'public.login_attempts', 'select,insert,update,delete')`)), `الجدول: لا قراءة ولا كتابة لـ ${who}`);
  ok(!(await priv(`has_sequence_privilege('${who}', 'public.login_attempts_id_seq', 'usage,select,update')`)), `التسلسل: مسحوب من ${who}`);
  ok(!(await priv(`has_function_privilege('${who}', 'public.log_login_attempt(text,text)', 'execute')`)), `log_login_attempt: ممنوعة على ${who}`);
  ok(!(await priv(`has_function_privilege('${who}', 'public.login_attempt_profile_id(text)', 'execute')`)), `login_attempt_profile_id: داخلية (ممنوعة على ${who})`);
}
ok(await priv(`has_function_privilege('service_role', 'public.log_login_attempt(text,text)', 'execute')`), 'log_login_attempt: للخدمة');
ok(await priv(`has_function_privilege('authenticated', 'public.sms_login_attempts(int)', 'execute')`)
  && !(await priv(`has_function_privilege('anon', 'public.sms_login_attempts(int)', 'execute')`)), 'sms_login_attempts: للمسجّلين (والدور يُفحص داخلها) لا للزائر');
ok(!(await priv(`has_schema_privilege('authenticated', 'auth', 'usage')`)), 'التطبيقات بلا أي وصول لـ auth (القراءة عبر SECURITY DEFINER فقط)');
let res = await as(P.O, `select count(*) from public.login_attempts`);
ok(!res.ok && /permission denied/.test(res.err), 'حتى المالك ما يقرأ الجدول مباشرة', res.err);
res = await as(P.O, `insert into public.login_attempts (phone, outcome) values ('96550000000', 'sent')`);
ok(!res.ok && /permission denied/.test(res.err), 'ولا يكتب فيه مباشرة', res.err);
res = await as(P.O, `select public.log_login_attempt('96550000000', 'sent')`);
ok(!res.ok && /permission denied/.test(res.err), 'ولا يستدعي التسجيل (الدالة الطرفية فقط)', res.err);
res = await as(P.O, `select public.sms_login_attempts()`, [], 'anon');
ok(!res.ok && /permission denied/.test(res.err), 'الزائر (anon) مرفوض', res.err);

// ── التحقق من المدخلات ──
for (const [ph, oc, m] of [['+96550001234', 'sent', 'رقم بعلامة +'], ['96520001234', 'sent', 'رقم أرضي'], ['9655000123', 'sent', 'رقم ناقص'],
  ['971500000000', 'sent', 'دولة أخرى'], ['96550001234', 'accepted', 'نتيجة غير معروفة'], ['96550001234', 'sent ', 'نتيجة بمسافة'],
  [null, 'sent', 'رقم فارغ'], ['96550001234', null, 'نتيجة فارغة'], ['123456', 'sent', 'رمز بدل رقم']]) {
  res = await log(ph, oc);
  ok(!res.ok && res.code === '22023', `مرفوض: ${m}`, res.err);
}
ok(Number(await priv(`count(*)::int from public.login_attempts`)) === 0, 'لا شيء انحفظ من المرفوض');

// ── البيانات ──
// K عضو: ٣ اليوم + ١ قبل يومين + ١ قبل ١٠ أيام (خارج ٧، داخل ٣٠)؛ دخل بعد آخر محاولة
await logAt('96550001234', 'sent', '10 seconds');
await logAt('96550001234', 'blocked', '20 seconds');
await logAt('96550001234', 'sent', '30 seconds');
await logAt('96550001234', 'failed', '-2 days -21 hours');
await logAt('96550001234', 'sent', '-10 days');
await db.exec(`update auth.users set last_sign_in_at = ${at('40 seconds')} where id = '${P.K}'`);
// U1 مجهول: ٥ في نفس الساعة أمس ← مريب
for (let i = 0; i < 5; i++) await logAt('96599990001', i === 4 ? 'sent' : 'blocked', `-1 day +2 hours +${i} minutes`);
// U2 مجهول: ٥ موزّعة على ٥ ساعات أمس ← غير مريب
for (let i = 0; i < 5; i++) await logAt('96599990002', 'sent', `-1 day +${2 + i} hours`);
// U3 مجهول: ٤ في ساعة واحدة ← غير مريب (الحد ٥)
for (let i = 0; i < 4; i++) await logAt('96599990003', 'unknown', `-1 day +5 hours +${i} minutes`);
// X: ملف منقول (حساب الدخول يشير له بـ app_metadata) — الوضع التجريبي
await logAt('96555500000', 'test', '-3 days');
// L: رقم الملف بصيغة قديمة (٨ أرقام)
await logAt('96560001111', 'sent', '-4 days');
// M2: آخر دخول قبل أول محاولة ← ما دخل
await logAt('96551112222', 'failed', '50 seconds');
await db.exec(`update auth.users set last_sign_in_at = ${at('-3 days')} where id = '${P.M2}'`);
// D: عضو سيُحذف ملفه
await logAt('96566600000', 'sent', '-5 days');

// ── مطابقة العضو وقت التسجيل ──
const stored = async ph => (await one(`select profile_id from public.login_attempts where phone = $1 order by id desc limit 1`, [ph])).profile_id;
ok(await stored('96550001234') === P.K, 'المطابقة: «+965…» في ملف العضو');
ok(await stored('96555500000') === P.X, 'المطابقة: حساب منقول ← ملفه من app_metadata.profile_id');
ok(await stored('96560001111') === P.L, 'المطابقة: صيغة قديمة (٨ أرقام)');
ok(await stored('96599990001') === null, 'المطابقة: رقم مجهول ← بلا ملف');

// ── قراءة المالك (٧ أيام افتراضياً) ──
let o = await read(P.O);
ok(o && o.items, 'المالك يقرأ (كمستخدم authenticated)', JSON.stringify(o));
ok(o.days === 7 && o.masked === false && o.retention_days === 30, 'المالك: ٧ أيام، بلا إخفاء، الحفظ ٣٠ يوماً');
let k = item(o, '50001234');
ok(k.phone === '+965 50001234' && k.phone_e164 === '+96550001234', 'المالك يرى الرقم كاملاً', k.phone);
ok(k.is_member && k.profile_id === P.K && k.name === 'كاظم علي حسن المحمدعلي' && k.member_status === 'active', 'العضو: الاسم والمعرّف والحالة');
ok(k.attempts_today === 3 && k.attempts_in_window === 4, 'العدد: ٣ اليوم، ٤ في ٧ أيام (محاولة ١٠ أيام خارجها)', `${k.attempts_today}/${k.attempts_in_window}`);
ok(k.sent === 2 && k.blocked === 1 && k.failed === 1 && k.unknown === 0 && k.test === 0, 'النتائج: ٢ أُرسلت، ١ محجوبة، ١ فشلت');
ok(k.last_outcome === 'sent', 'آخر نتيجة');
ok(new Date(k.first_at).getTime() === new Date((await one(`select (${at('-2 days -21 hours')})::text t`)).t).getTime()
  && new Date(k.last_at).getTime() === new Date((await one(`select (${at('30 seconds')})::text t`)).t).getTime(), 'أول وآخر محاولة في الفترة');
ok(k.logged_in === true && k.last_sign_in_at !== null, 'دخل: آخر دخول بعد أول محاولة');
ok(k.suspicious === false && k.max_in_hour === 3, 'غير مريب (٣ في ساعة)');
const u1 = item(o, '99990001'), u2 = item(o, '99990002'), u3 = item(o, '99990003');
ok(!u1.is_member && u1.profile_id === null && u1.name === null && u1.member_status === null, 'رقم مجهول: ليس عضواً');
ok(u1.suspicious === true && u1.max_in_hour === 5 && u1.blocked === 4 && u1.sent === 1, 'مريب: ٥ في ساعة واحدة');
ok(u2.suspicious === false && u2.max_in_hour === 1 && u2.attempts_in_window === 5, 'غير مريب: ٥ موزّعة على ٥ ساعات');
ok(u3.suspicious === false && u3.max_in_hour === 4 && u3.unknown === 4, 'غير مريب: ٤ في ساعة (الحد ٥)');
ok(u1.logged_in === false && u1.last_sign_in_at === null, 'بلا حساب دخول ← ما دخل');
const x = item(o, '55500000');
ok(x.is_member && x.profile_id === P.X && x.name === 'ياسر ملف منقول' && x.test === 1, 'الحساب المنقول يظهر باسم ملفه، والتجريبي يُعدّ');
ok(x.logged_in === false, 'آخر دخول (قبل ٢٠ يوماً) قبل المحاولة ← ما دخل');
ok(item(o, '60001111').name === 'ليث رقم قديم', 'صيغة الرقم القديمة تُطابق');
const m2 = item(o, '51112222');
ok(m2.is_member && m2.logged_in === false && m2.failed === 1, 'دخل قبل المحاولة لا بعدها ← ما دخل');
ok(o.items.every((it, i) => i === 0 || it.last_at <= o.items[i - 1].last_at), 'الأحدث أولاً');
ok(o.items[0].phone === '+965 51112222', 'أول صف = آخر محاولة', o.items[0].phone);
ok(o.totals.phones === 8 && o.totals.attempts === 22 && o.totals.unknown_numbers === 3 && o.totals.suspicious === 1,
  'الإجماليات: ٨ أرقام، ٢٢ محاولة، ٣ مجهولة، ١ مريب', JSON.stringify(o.totals));
const keys = 'attempts_in_window,attempts_today,blocked,failed,first_at,is_member,last_at,last_outcome,last_sign_in_at,logged_in,max_in_hour,member_status,name,phone,phone_e164,profile_id,sent,suspicious,test,unknown';
ok(o.items.every(it => Object.keys(it).sort().join(',') === keys), 'كل صف بالحقول المعروفة فقط');
ok(Object.keys(o).sort().join(',') === 'days,generated_at,items,masked,retention_days,totals', 'شكل الرد');

// ── الفترة ──
o = await read(P.O, 1);
k = item(o, '50001234');
ok(o.days === 1 && k.attempts_in_window === 3 && k.attempts_today === 3 && o.totals.phones === 2, 'يوم واحد: اليوم فقط (كاظم ٣، ومهدي)', JSON.stringify(o.totals));
o = await read(P.O, 30);
ok(item(o, '50001234').attempts_in_window === 5, '٣٠ يوماً: تشمل محاولة ١٠ أيام');
ok((await read(P.O, 0)).days === 1 && (await read(P.O, 999)).days === 30 && (await read(P.O, null)).days === 7, 'الأيام تُحصر بين ١ و٣٠ (الفارغ = ٧)');

// ── قراءة المدير: الرقم مخفي ──
o = await read(P.A);
ok(o && o.masked === true, 'المدير يقرأ والرد «مخفي»');
ok(o.items.find(it => it.profile_id === P.K).phone === '+965 5000••34', 'المدير: «+965 5000••34» (أول ٤ وآخر خانتين)');
ok(o.items.every(it => /^\+965 [0-9]{4}••[0-9]{2}$/.test(it.phone) && it.phone_e164 === null), 'المدير: كل الأرقام مخفية وبلا phone_e164');
const text = JSON.stringify(o);
const allPhones = (await db.query(`select distinct phone from public.login_attempts`)).rows.map(z => z.phone);
ok(allPhones.every(ph => !text.includes(ph.slice(3)) && !text.includes(ph) && !text.includes(ph.slice(3, 9))),
  'المدير: لا رقم كامل ولا ٦ خانات متتالية منه في أي مكان من الرد');
ok(o.totals.phones === 8 && o.items.find(it => it.profile_id === P.K).attempts_today === 3, 'المدير: نفس الأعداد');

// ── المرفوضون ──
for (const [who, m] of [[P.M, 'العضو'], [P.MON, 'المراقب'], [P.SUP, 'المشرف'], [P.FA, 'المدير المجمّد'], [P.PEND, 'المعلّق'], [P.NOBODY, 'حساب بلا ملف']]) {
  res = await read(who);
  ok(res && res.ok === false && res.code === '42501', `${m}: مرفوض (42501)`, res.err);
}

// ── حذف ملف عضو: لا يتعطل ولا يُعطّل ──
res = await db.query(`delete from public.profiles where id = '${P.D}'`).then(() => ({ ok: true }), e => ({ ok: false, err: e.message }));
ok(res.ok, 'حذف ملف عضو له محاولات يمر (بلا مفتاح أجنبي)', res.err);
ok(await stored('96566600000') === P.D, 'سطر المحاولة باقٍ كما هو');
o = await read(P.O);
const d = item(o, '66600000');
ok(d && !d.is_member && d.profile_id === null && d.name === null, 'بعد الحذف: يظهر رقماً مجهولاً (المعرّف القديم يُهمل)');
// إعادة الربط: ملف جديد بنفس الرقم يُطابق وقت القراءة
await db.exec(`insert into public.profiles (id, first_name, full_name, gender, role, status, phone_number) values
  ('${id(40)}', 'دانة', 'ملف جديد بنفس الرقم', 'male', 'member', 'active', '+96566600000')`);
ok(item(await read(P.O), '66600000').profile_id === id(40), 'ملف جديد بنفس الرقم يُطابق وقت القراءة');

// ── الحفظ ٣٠ يوماً (حذف محدود) ──
await db.exec(`insert into public.login_attempts (phone, outcome, created_at)
  select '9655' || lpad(i::text, 7, '0'), 'sent', now() - interval '31 days' - (i || ' minutes')::interval from generate_series(1, 250) i;
  insert into public.login_attempts (phone, outcome, created_at) values ('96550009999', 'sent', now() - interval '29 days');`);
const old = async () => Number(await priv(`count(*)::int from public.login_attempts where created_at < now() - interval '30 days'`));
ok(await old() === 250, 'قبل: ٢٥٠ سطراً أقدم من ٣٠ يوماً');
await log('96550001234', 'sent');
ok(await old() === 50, 'تسجيل واحد يحذف ٢٠٠ فقط (محدود)', String(await old()));
await log('96550001234', 'blocked');
ok(await old() === 0, 'التسجيل التالي يكمل الباقي');
ok(Number(await priv(`count(*)::int from public.login_attempts where phone = '96550009999'`)) === 1, 'سطر عمره ٢٩ يوماً باقٍ');
ok(item(await read(P.O, 30), '50009999').attempts_in_window === 1, '... ويظهر في فترة ٣٠ يوماً');

// ── الحد الأعلى ٢٠٠ رقم ──
await db.exec(`insert into public.login_attempts (phone, outcome, created_at)
  select '9656' || lpad(i::text, 7, '0'), 'sent', now() - (i || ' seconds')::interval from generate_series(1, 250) i;`);
o = await read(P.O);
ok(o.items.length === 200 && o.totals.phones > 250, `القائمة ٢٠٠ رقم كحد أعلى، والإجمالي يعدّ الكل (${o.totals.phones})`);
ok(o.items.every((it, i) => i === 0 || it.last_at <= o.items[i - 1].last_at), 'الأحدث أولاً مع الحد');

// ── KWT SMS ما تأثر ──
await db.exec(`update public.kwtsms_deliveries set created_at = created_at - interval '2 seconds'`);
res = await as(null, `select public.reserve_kwtsms_send($1, $2, false) r`, ['a'.repeat(64), 'b'.repeat(64)], 'service_role');
ok(res.ok && res.rows[0].r === 'send', 'reserve_kwtsms_send يعمل كما هو', res.err);

// ── التراجع ثم إعادة التطبيق ──
await db.exec(RB);
ok(Number(await priv(`count(*)::int from pg_proc where proname in ('log_login_attempt','sms_login_attempts','login_attempt_profile_id')`)) === 0
  && (await priv(`to_regclass('public.login_attempts')`)) === null, 'التراجع: الجدول والدوال الثلاث حُذفت');
for (const sig of KWT_FNS) ok(await md5(sig) === BEFORE[sig], `التراجع: ${sig.split('(')[0]} كما كانت`);
await db.exec(MIG);
ok((await log('96550001234', 'sent')).ok && (await read(P.O)).totals.attempts === 1, 'إعادة التطبيق بعد التراجع تعمل');

console.log(`\nالنتيجة: ${pass} نجحت، ${fail} فشلت`);
process.exit(fail ? 1 : 0);
