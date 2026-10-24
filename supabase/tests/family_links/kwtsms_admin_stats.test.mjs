// تجربة 20261020150000 (السجل اليومي + سبب الفشل + العتبات) و 20261020151000 (قراءة الإدارة + دوال kwtsms-admin)
// على قاعدة محلية معزولة — لا تلمس السيرفر. التشغيل: cd supabase/tests/family_links && node kwtsms_admin_stats.test.mjs
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
process.on('unhandledRejection', e => { console.log('خطأ:', e.message, (e.query ?? '').slice(0, 300)); process.exit(2); });
const REPO = fileURLToPath(new URL('../../', import.meta.url));
const r = f => readFileSync(`${REPO}/${f}`, 'utf8');
// تعريفات السيرفر الحي (pg_get_functiondef، قراءة فقط ٢٠٢٦-١٠-٢٠)
const LIVE_MD5 = {
  finish: '252b46e576773a8557414844133ddd16',
  status: '31ce0e27546e4f3435e79200a7db6e0e',
  reserve: '131a68ec220bc9f7b8de5b7e69ef3c43',
};
const db = new PGlite();
await db.exec(`
do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role; end if;
end $$;
create table public.profiles (id uuid primary key, role text, status text, phone_number text);
create table public.notifications (id uuid primary key default gen_random_uuid(), target_member_id uuid,
  created_by uuid, title text, body text, kind text, is_read boolean default false, created_at timestamptz default now());
create or replace function public.current_user_role() returns text language sql stable as $$
  select nullif(current_setting('test.role', true), '') $$;
-- app_settings: سطر واحد بأعمدة + سياستا السيرفر الحي (القراءة للكل، التعديل للمالك)
create table public.app_settings (id uuid primary key default gen_random_uuid(),
  allow_new_registrations boolean not null default true, updated_at timestamptz not null default now(), updated_by uuid);
insert into public.app_settings default values;
alter table public.app_settings enable row level security;
grant select, update on public.app_settings to authenticated;
create policy "Authenticated users can read app_settings" on public.app_settings for select to authenticated using (true);
create policy "Owner can update app_settings" on public.app_settings for update to authenticated
  using (public.current_user_role() = 'owner') with check (public.current_user_role() = 'owner');
`);
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
await db.exec(`insert into public.profiles values ('${id(1)}','owner','active','+96590000001'),('${id(2)}','admin','active',null),
  ('${id(3)}','monitor','active',null),('${id(4)}','admin','frozen',null);`);
let pass = 0, fail = 0;
const ok = (c, m) => { if (c) { pass++; console.log('✓', m); } else { fail++; console.log('✗', m); } };
const one = async (q, p = []) => (await db.query(q, p)).rows[0];
const md5 = async sig => (await one(`select md5(pg_get_functiondef('${sig}'::regprocedure)) m`)).m;
const throws = async (q, p = []) => { try { await db.query(q, p); return null; } catch (e) { return e; } };
const hex = n => n.toString(16).padStart(64, '0');
let seq = 1;
const reserve = async (ph, test = false) => {
  const ev = hex(seq++);
  // حد «٥ بالثانية» العام: نباعد الأوقات بدل الانتظار
  await db.exec(`update public.kwtsms_deliveries set created_at = created_at - interval '2 seconds'`);
  const res = (await one(`select public.reserve_kwtsms_send($1,$2,$3) r`, [ev, hex(ph), test])).r;
  if (res !== 'send') throw Error('reserve ' + res);
  return ev;
};
// يحاكي send-sms-kwtsms: الاستدعاء بالأسماء (القديم بخمسة، والجديد مع p_error_code لما يكون فيه سبب)
const finish = (ev, outcome, charged, balance, code) => code === undefined
  ? db.query(`select public.finish_kwtsms_send(p_event => $1, p_outcome => $2, p_msgid => $3, p_charged => $4, p_balance => $5)`,
      [ev, outcome, outcome === 'accepted' ? 'm' + ev.slice(-6) : null, charged, balance])
  : db.query(`select public.finish_kwtsms_send(p_event => $1, p_outcome => $2, p_msgid => $3, p_charged => $4, p_balance => $5, p_error_code => $6)`,
      [ev, outcome, outcome === 'accepted' ? 'm' + ev.slice(-6) : null, charged, balance, code]);
const send = async (balance, outcome = 'accepted', opts = {}) => {
  const ev = await reserve(10000 + seq, opts.test ?? false);
  if (opts.at) await db.query(`update public.kwtsms_deliveries set created_at = $2 where event_hash = $1`, [ev, opts.at]);
  await finish(ev, outcome, outcome === 'accepted' ? (opts.charged ?? 1) : null, outcome === 'accepted' ? balance : null, opts.code);
  return ev;
};
const count = async (w = 'true') => Number((await one(`select count(*)::int n from public.notifications where ${w}`)).n);
const stats = async day => one(`select * from public.kwtsms_daily_stats where day = $1::date`, [day]);
const today = (await one(`select (now() at time zone 'Asia/Kuwait')::date::text d`)).d;
const role = v => db.exec(`set test.role = '${v}'`);
const overview = async () => (await one(`select public.sms_admin_overview() o`)).o;

// ── قبل: نفس تعريفات السيرفر الحي ──
for (const f of ['20261019200000_kwtsms_delivery_guard', '20261019210000_kwtsms_low_balance_alert',
  '20261019220000_kwtsms_cooldown_one_minute', '20261019230000_kwtsms_urgent_alert_12h']) await db.exec(r(`migrations/${f}.sql`));
ok(await md5('public.finish_kwtsms_send(text,text,text,numeric,numeric)') === LIVE_MD5.finish, 'قبل: finish_kwtsms_send = الحي حرفياً');
ok(await md5('public.sms_balance_status()') === LIVE_MD5.status, 'قبل: sms_balance_status = الحي حرفياً');
ok(await md5('public.reserve_kwtsms_send(text,text,boolean)') === LIVE_MD5.reserve, 'قبل: reserve_kwtsms_send = الحي حرفياً');
// إرسالات موجودة قبل الترحيل (تُعبّأ في السجل اليومي)
await send(60); await send(null, 'failed'); await send(59, 'accepted', { test: true });

// ── الترحيلان ──
await db.exec(r('migrations/20261020150000_kwtsms_daily_stats.sql'));
await db.exec(r('migrations/20261020151000_kwtsms_admin_overview.sql'));
let s = await stats(today);
ok(s && s.sends === 2 && s.accepted === 1 && s.failed === 1 && s.test_sends === 1 && Number(s.points) === 1
  && Number(s.last_balance) === 60, 'التعبئة: إرسالات اليوم الموجودة دخلت السجل (٢ فعلي، ١ تجريبي، رصيد ٦٠)');
ok(Number((await one(`select count(*)::int n from pg_proc where proname = 'finish_kwtsms_send'`)).n) === 1,
  'finish_kwtsms_send نسخة واحدة فقط (لا تعارض في PostgREST)');
ok(await md5('public.reserve_kwtsms_send(text,text,boolean)') === LIVE_MD5.reserve, 'reserve_kwtsms_send ما تغيّرت');

// ── سلوك التنبيه القديم بالقيم الافتراضية (نفس تجربة 20261019230000) ──
ok(await count() === 0, 'لا تنبيه قبل البدء');
await send(120); ok(await count() === 0, 'رصيد ١٢٠: لا تنبيه');
await send(45);  ok(await count(`kind='sms_balance_low'`) === 2, 'رصيد ٤٥: تنبيه للمالك والمدير المفعّلين فقط (٢)');
ok(await count(`body like 'باقي 45 نقطة%' and title = 'رصيد رسائل الدخول قليل'`) === 2, 'النص والعنوان كما هما');
await send(44);  ok(await count() === 2, 'رصيد ٤٤ بنفس اليوم: ما يتكرر');
await send(9);   ok(await count(`title like 'عاجل%'`) === 2, 'رصيد ٩: تنبيه عاجل رغم تنبيه اليوم');
await send(8);   ok(await count(`title like 'عاجل%'`) === 2, 'رصيد ٨ بعد قليل: ما يتكرر العاجل');
await db.exec(`update public.notifications set created_at = now() - interval '4 hours' where title like 'عاجل%'`);
await send(7);   ok(await count(`title like 'عاجل%'`) === 2, 'بعد ٤ ساعات: ما يتكرر (١٢ ساعة)');
await db.exec(`update public.notifications set created_at = now() - interval '13 hours' where title like 'عاجل%'`);
await send(7);   ok(await count(`title like 'عاجل%'`) === 4, 'بعد ١٣ ساعة: العاجل يتكرر');
let before = await count();
await send(5, 'failed', { code: 'ERR010' }); ok(await count() === before, 'إرسال فاشل: لا تنبيه');
await db.query(`select public.finish_kwtsms_send($1,'accepted','m9',1,2)`, [hex(999999)]);
ok(await count() === before, 'حدث غير محجوز: لا تنبيه ولا يدخل السجل');
// العادي ينتظر ٢٤ ساعة من آخر تنبيه رصيد (عادي أو عاجل) — كما هو على السيرفر
await db.exec(`update public.notifications set created_at = now() - interval '20 hours'`);
await send(30); ok(await count(`title = 'رصيد رسائل الدخول قليل'`) === 2, 'بعد ٢٠ ساعة: العادي ما يتكرر');
await db.exec(`update public.notifications set created_at = now() - interval '25 hours'`);
await send(30); ok(await count(`title = 'رصيد رسائل الدخول قليل'`) === 4, 'بعد ٢٥ ساعة: العادي يتكرر');

// ── السجل اليومي يوم بيوم (يوم معزول، أرصدة عالية بلا تنبيه) ──
const D = '2026-09-01', at = h => `${D} ${h}+00`;
await send(300, 'accepted', { at: at('06:00:00') });
await send(280, 'accepted', { at: at('07:00:00') });
await send(null, 'failed', { at: at('08:00:00'), code: 'ERR028' });
await send(null, 'unknown', { at: at('08:30:00'), code: 'TIMEOUT' });
await send(null, 'failed', { at: at('08:40:00') });
await send(270, 'accepted', { at: at('09:00:00') });
await send(999, 'accepted', { at: at('09:10:00'), test: true });          // الوضع التجريبي
// اختبار المالك
const adminEv = hex(seq++);
ok((await one(`select public.reserve_kwtsms_admin_test($1,$2,false) r`, [adminEv, hex(1)])).r === 'send', 'اختبار المالك: أول حجز');
await db.query(`update public.kwtsms_deliveries set created_at = $2 where event_hash = $1`, [adminEv, at('09:20:00')]);
await finish(adminEv, 'accepted', 1, 269);
await send(500, 'accepted', { at: `${D} 21:30:00+00` });                   // ٠٠:٣٠ بتوقيت الكويت ← اليوم التالي
s = await stats(D);
ok(s.sends === 6 && s.accepted === 3 && s.failed === 2 && s.unknown === 1, 'السجل: ٦ فعلية (٣ مقبولة، ٢ فاشلة، ١ مجهولة)');
ok(s.test_sends === 2, 'السجل: التجريبي واختبار المالك ← «تجريبية» (٢) لا رموز دخول');
ok(Number(s.points) === 4, 'السجل: النقاط ٤ (٣ رموز + اختبار المالك؛ التجريبي بلا خصم)');
ok(Number(s.first_balance) === 300 && Number(s.last_balance) === 269, 'السجل: أول رصيد ٣٠٠ وآخر رصيد ٢٦٩ (التجريبي لا يحسب)');
const s2 = await stats('2026-09-02');
ok(s2 && s2.sends === 1 && Number(s2.last_balance) === 500, 'حد اليوم بتوقيت الكويت: ٢١:٣٠ UTC = اليوم التالي');
// سبب الفشل (إرسالات اليوم — صفوف يوم ٩/١ تنحذف مع أول حجز بعدها لأنها أقدم من يومين)
const evFail = await send(null, 'failed', { code: 'ERR028' });
const evUnk = await send(null, 'unknown', { code: 'TIMEOUT' });
const evBad = await send(null, 'failed', { code: 'bad code!' });
const evOkCode = await send(270, 'accepted', { code: 'ERR003' });
const code = async ev => (await one(`select error_code, outcome from public.kwtsms_deliveries where event_hash = $1`, [ev]));
ok((await code(evFail)).error_code === 'ERR028', 'سبب الفشل محفوظ (ERR028)');
ok((await code(evUnk)).error_code === 'TIMEOUT' && (await code(evUnk)).outcome === 'unknown', 'المجهول مع سببه (TIMEOUT)');
ok((await code(evBad)).error_code === null && (await code(evBad)).outcome === 'failed', 'سبب غريب يُهمل والنتيجة تنحفظ');
ok((await code(evOkCode)).error_code === null, 'المقبول بلا سبب فشل');

// ── قراءة الإدارة ──
for (const v of ['', 'monitor', 'supervisor', 'member', 'frozen']) {
  await role(v);
  const e = await throws(`select public.sms_admin_overview()`);
  ok(e && e.code === '42501', `القراءة مرفوضة لـ «${v || 'بلا دور'}» (42501)`);
}
await role('admin'); let o = await overview(); ok(!!o.totals, 'المدير يقرأ');
await role('owner'); o = await overview(); ok(!!o.totals, 'المالك يقرأ');
s = await stats(today);
ok(o.totals.today.sends === s.sends && o.totals.today.accepted === s.accepted && Number(o.totals.today.points) === Number(s.points),
  'أرقام اليوم = السجل');
ok(Number(o.totals.today.acceptance_pct) === Math.round(1000 * s.accepted / s.sends) / 10, 'نسبة القبول');
const hour = Number((await one(`select count(*)::int n from public.kwtsms_deliveries where created_at > now() - interval '1 hour'`)).n);
ok(o.hour.count === hour && o.hour.cap === 100, `عدّاد الساعة (${hour} من ١٠٠)`);
ok(o.alerts.low_threshold === 50 && o.alerts.urgent_threshold === 10 && o.alerts.low_repeat_hours === 24
  && o.alerts.urgent_repeat_hours === 12, 'إعدادات التنبيه الافتراضية = الحالية');
// ٦٠ إرسالاً إضافياً ← آخر ٥٠ فقط
await db.exec(`insert into public.kwtsms_deliveries(event_hash, phone_hash, test_mode, created_at, outcome)
  select md5('e'||i)||md5('e'||i), md5('p'||i)||md5('q'||i), false, now() - (i || ' minutes')::interval - interval '2 hours', 'accepted'
  from generate_series(1, 60) i`);
o = await overview();
ok(o.recent.length === 50, 'آخر ٥٠ إرسالاً فقط');
ok(o.recent.every((x, i) => i === 0 || x.at <= o.recent[i - 1].at), 'الأحدث أولاً');
const allowed = 'admin_test,at,balance_after,delivery_checked_at,delivery_status,error_code,msgid,outcome,phone_tail,points,test';
ok(o.recent.every(x => Object.keys(x).sort().join(',') === allowed), 'كل صف بالحقول المسموحة فقط (بلا بصمة رقم ولا حدث)');
const text = JSON.stringify(o);
const hashes = (await db.query(`select phone_hash h from public.kwtsms_deliveries union select event_hash from public.kwtsms_deliveries`)).rows.map(x => x.h);
ok(!/[a-f0-9]{64}/.test(text) && hashes.every(h => !text.includes(h.slice(0, 12)) && !text.includes(h.slice(-12))),
  'لا بصمة كاملة ولا جزء منها أكثر من ٤ خانات');
ok(o.recent.every(x => /^[a-f0-9]{4}$/.test(x.phone_tail)), 'آخر ٤ خانات فقط للتمييز');

// ── العتبات من الإعدادات ──
await db.exec(`delete from public.notifications`);
await db.exec(`update public.app_settings set sms_low_threshold = 100, sms_urgent_threshold = 30`);
await send(80); ok(await count(`title = 'رصيد رسائل الدخول قليل'`) === 2, 'عتبة ١٠٠: رصيد ٨٠ ينبّه');
await send(25); ok(await count(`title like 'عاجل%'`) === 2, 'عتبة العاجل ٣٠: رصيد ٢٥ عاجل');
await role('owner');
ok((await one(`select public.sms_balance_status() s`)).s.low === true, 'sms_balance_status يتبع العتبة');
o = await overview(); ok(o.balance_state === 'urgent' && Number(o.balance) === 25, 'القراءة: حالة الرصيد حسب العتبات');
await db.exec(`update public.app_settings set sms_low_threshold = 0, sms_urgent_threshold = 0`);
before = await count(); await send(3); ok(await count() === before, 'العتبة ٠ تطفئ التنبيه');
await db.exec(`update public.app_settings set sms_low_threshold = 50, sms_urgent_threshold = 10, sms_urgent_repeat_hours = 3`);
await db.exec(`update public.notifications set created_at = now() - interval '4 hours' where title like 'عاجل%'`);
await send(5); ok(await count(`title like 'عاجل%'`) === 4, 'فاصل العاجل ٣ ساعات من الإعدادات: يتكرر بعد ٤');
await db.exec(`update public.app_settings set sms_urgent_repeat_hours = 12`);
for (const [q, m] of [[`sms_urgent_threshold = 60`, 'العاجل أكبر من المنخفض'], [`sms_low_repeat_hours = 0`, 'فاصل صفر'],
  [`sms_low_threshold = -1`, 'عتبة سالبة'], [`sms_urgent_repeat_hours = 200`, 'فاصل فوق أسبوع']]) {
  ok(!!(await throws(`update public.app_settings set ${q}`)), `مرفوض: ${m}`);
}
await db.exec(`set role authenticated`);
await role('admin');
ok((await db.query(`update public.app_settings set sms_low_threshold = 40`)).affectedRows === 0, 'المدير ما يعدّل العتبات');
await role('owner');
ok((await db.query(`update public.app_settings set sms_low_threshold = 40`)).affectedRows === 1, 'المالك يعدّل العتبات');
await db.exec(`reset role`);
await db.exec(`update public.app_settings set sms_low_threshold = 50`);

// ── اختبار المالك: مرة كل ١٠ دقائق ──
await db.exec(`update public.kwtsms_deliveries set created_at = created_at - interval '2 seconds'`);
ok((await one(`select public.reserve_kwtsms_admin_test($1,$2,false) r`, [hex(seq++), hex(2)])).r === 'send', 'اختبار: أول مرة');
await db.exec(`update public.kwtsms_deliveries set created_at = created_at - interval '5 minutes' where admin_test and created_at > now() - interval '1 hour'`);
ok((await one(`select public.reserve_kwtsms_admin_test($1,$2,false) r`, [hex(seq++), hex(2)])).r === 'wait', 'اختبار: بعد ٥ دقائق ممنوع (wait)');
await db.exec(`update public.kwtsms_deliveries set created_at = created_at - interval '6 minutes' where admin_test and created_at > now() - interval '1 hour'`);
const ev2 = hex(seq++);
ok((await one(`select public.reserve_kwtsms_admin_test($1,$2,false) r`, [ev2, hex(2)])).r === 'send', 'اختبار: بعد ١١ دقيقة مسموح');
ok((await one(`select public.reserve_kwtsms_send($1,$2,false) r`, [hex(seq++), hex(2)])).r === 'blocked',
  'رمز دخول لنفس الرقم خلال ٥٠ ثانية من الاختبار: ينتظر (ما يتصادمان)');
ok(!!(await throws(`select public.reserve_kwtsms_admin_test('x', $1, false)`, [hex(2)])), 'اختبار: مدخلات غير صالحة مرفوضة');
const sBefore = await stats(today);
await finish(ev2, 'accepted', 1, 400);
const sAfter = await stats(today);
ok(sAfter.sends === sBefore.sends && sAfter.test_sends === sBefore.test_sends + 1 && Number(sAfter.points) === Number(sBefore.points) + 1,
  'اختبار المالك: «تجريبي» + نقطته، لا يغيّر عدد رموز الدخول');

// ── حالة الوصول والرصيد الحي ──
ok((await one(`select public.record_kwtsms_delivery_status($1,'sent') f`, ['m' + ev2.slice(-6)])).f === true, 'status: محفوظ لرسالة معروفة');
const ds = await one(`select delivery_status, delivery_checked_at from public.kwtsms_deliveries where event_hash = $1`, [ev2]);
ok(ds.delivery_status === 'sent' && ds.delivery_checked_at !== null, 'status: الحالة ووقت الفحص');
ok((await one(`select public.record_kwtsms_delivery_status('nope-123','sent') f`)).f === false, 'status: رسالة غير معروفة ← false');
ok(!!(await throws(`select public.record_kwtsms_delivery_status('m1', 'x;drop table')`)), 'status: نص غريب مرفوض');
await db.query(`select public.record_kwtsms_balance(750)`);
await role('admin'); o = await overview();
ok(Number(o.balance) === 750 && o.balance_state === 'ok', '«تحديث الرصيد الآن» يظهر في القراءة (٧٥٠، جيد)');
ok(!!(await throws(`select public.record_kwtsms_balance(-1)`)), 'رصيد سالب مرفوض');

// ── الصلاحيات ──
const fx = (who, sig) => one(`select has_function_privilege('${who}', '${sig}', 'execute') x`).then(x => x.x);
for (const sig of ['public.finish_kwtsms_send(text,text,text,numeric,numeric,text)', 'public.reserve_kwtsms_admin_test(text,text,boolean)',
  'public.record_kwtsms_delivery_status(text,text)', 'public.record_kwtsms_balance(numeric)']) {
  ok(!(await fx('authenticated', sig)) && !(await fx('anon', sig)) && await fx('service_role', sig), `${sig.split('(')[0]}: للخدمة فقط`);
}
ok(await fx('authenticated', 'public.sms_admin_overview()') && !(await fx('anon', 'public.sms_admin_overview()')),
  'sms_admin_overview: للمسجّلين (والدور يُفحص داخلها) لا للزائر');
ok(!(await one(`select has_table_privilege('authenticated','public.kwtsms_daily_stats','select') x`)).x
  && (await one(`select relrowsecurity x from pg_class where oid = 'public.kwtsms_daily_stats'::regclass`)).x,
  'السجل اليومي مقفول عن التطبيقات (RLS بلا سياسات)');

// ── السجل يبقى بعد حذف الإرسالات (يومان) ──
await reserve(77);
ok(Number((await one(`select count(*)::int n from public.kwtsms_deliveries where created_at < now() - interval '2 days'`)).n) === 0,
  'الحذف بعد يومين يعمل كما هو');
s = await stats(D);
ok(s && s.sends === 6 && Number(s.last_balance) === 269, 'سجل ٢٠٢٦-٠٩-٠١ باقٍ بعد حذف إرسالاته');

// ── التراجع ──
await db.exec(r('rollback/20261020151000_kwtsms_admin_overview_rollback.sql'));
await db.exec(r('rollback/20261020150000_kwtsms_daily_stats_rollback.sql'));
ok(await md5('public.finish_kwtsms_send(text,text,text,numeric,numeric)') === LIVE_MD5.finish, 'التراجع: finish_kwtsms_send = الحي حرفياً');
ok(await md5('public.sms_balance_status()') === LIVE_MD5.status, 'التراجع: sms_balance_status = الحي حرفياً');
ok(await md5('public.reserve_kwtsms_send(text,text,boolean)') === LIVE_MD5.reserve, 'التراجع: reserve_kwtsms_send = الحي');
ok(!(await fx('authenticated', 'public.finish_kwtsms_send(text,text,text,numeric,numeric)'))
  && await fx('service_role', 'public.finish_kwtsms_send(text,text,text,numeric,numeric)'), 'التراجع: صلاحيات finish كما كانت');
const left = (await one(`select
  (select count(*)::int from pg_proc where proname in ('sms_admin_overview','reserve_kwtsms_admin_test','record_kwtsms_delivery_status','record_kwtsms_balance')) f,
  (select count(*)::int from pg_proc where proname = 'finish_kwtsms_send') fin,
  (select count(*)::int from information_schema.tables where table_name = 'kwtsms_daily_stats') t,
  (select count(*)::int from information_schema.columns where (table_name = 'kwtsms_deliveries' and column_name in ('error_code','delivery_status','delivery_checked_at','admin_test'))
     or (table_name = 'app_settings' and column_name like 'sms_%')) c`));
ok(left.f === 0 && left.fin === 1 && left.t === 0 && left.c === 0, 'التراجع: لا دوال ولا جدول ولا أعمدة جديدة باقية');
await db.exec(`delete from public.notifications`);
await send(45); ok(await count() === 2, 'بعد التراجع: التنبيه القديم يعمل');

console.log(`\n${pass} نجح، ${fail} فشل`);
process.exit(fail ? 1 : 0);
