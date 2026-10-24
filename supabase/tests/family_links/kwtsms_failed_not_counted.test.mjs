// تجربة 20261023140000 (الفاشل لا يُحسب + «فك القفل» يصفّر الحدود) — قاعدة محلية معزولة.
import { makeDb, one, read, counter, mig } from './app_config_env.mjs';
const ok = counter();
const M = read('migrations/20261023140000_kwtsms_failed_not_counted.sql');
const RB = read('rollback/20261023140000_kwtsms_failed_not_counted_rollback.sql');
const db = await makeDb();
await db.exec(mig('config'));
await db.exec(`
  alter table public.app_settings add column if not exists sms_per_number_hour int default 3,
    add column if not exists sms_all_hour int default 100, add column if not exists sms_sender text;
  create table public.kwtsms_deliveries (event_hash text primary key, phone_hash text not null,
    created_at timestamptz not null default clock_timestamp(), test_mode boolean not null,
    outcome text not null default 'pending', provider_msgid text, points_charged numeric, balance_after numeric);
  create table if not exists public.notifications (id uuid primary key default gen_random_uuid(), target_member_id uuid,
    title text, body text, kind text, created_by uuid, is_read boolean default false, created_at timestamptz default now());`);
await db.exec(read('migrations/20261023100000_kwtsms_request_lock.sql'));
await db.exec(read('migrations/20261023120000_kwtsms_unlock_number.sql'));
await db.exec(read('migrations/20261023130000_kwtsms_one_code.sql'));
// الحالة الحية من ملف التراجع
await db.exec(RB.slice(0, RB.indexOf('drop table')));
const md5 = async () => (await one(db, `select md5(pg_get_functiondef('public.reserve_kwtsms_send(text,text,boolean,integer)'::regprocedure)) m`)).m;
ok.ok(await md5() === 'c345c799f3d47c41c2dab38d4f31e7a9', 'ملف التراجع = الحي');
await db.exec(M);
await db.exec(`update public.app_settings set sms_per_number_hour = 3, sms_wait_seconds = 60`);
await db.exec(`update public.app_config set value = '120' where key = 'sms_one_code_seconds';
  update public.app_config set value = '3' where key = 'sms_daily_per_number'`);
const hex = n => n.toString(16).padStart(64, '0'); let ev = 1;
const reserve = p => one(db, `select public.reserve_kwtsms_send($1,$2,false,2) r`, [hex(9000 + ev++), p]).then(x => x.r);
const age = s => db.exec(`update public.kwtsms_deliveries set created_at = created_at - interval '${s} seconds'; update public.kwtsms_request_log set created_at = created_at - interval '${s} seconds'; update public.kwtsms_cap_resets set reset_at = reset_at - interval '${s} seconds'`);
const fail = () => db.exec(`update public.kwtsms_deliveries set outcome = 'failed' where created_at = (select max(created_at) from public.kwtsms_deliveries)`);
const A = hex(1);
ok.ok((await reserve(A)).startsWith('send'), 'الأول يُرسل');
await db.exec(`update public.kwtsms_deliveries set outcome = 'accepted'`); await age(130);
ok.ok((await reserve(A)).startsWith('send'), 'الثاني بعد دقيقتين'); await age(130);
ok.ok((await reserve(A)).startsWith('send'), 'الثالث'); await fail(); await age(5);
ok.ok((await reserve(A)).startsWith('send'), 'الثالث فشل ← لا يُحسب: لا مهلة دقيقتين ولا حد ٣');
await age(130);
const r = await reserve(A);
ok.ok(r.startsWith('blocked:'), 'بعد ٣ ناجحة ← الحد', r);
const u = await one(db, `select public.kwtsms_unlock_number($1) j`, [A]);
ok.ok(u.j.caps_reset === true, 'الفك يرجع تصفير الحدود');
ok.ok((await reserve(A)).startsWith('send'), 'بعد الفك يُرسل فوراً');
ok.ok((await one(db, `select count(*)::int n from public.kwtsms_deliveries where phone_hash = $1`, [A])).n === 5, 'سجل الإرسال لم يُحذف');
await age(5);
ok.ok((await reserve(A)).startsWith('blocked:'), 'بعد الفك تعود مهلة الدقيقتين للإرسال الجديد');
const B = hex(2);
ok.ok((await reserve(B)).startsWith('send'), 'رقم آخر لا يتأثر');
await db.exec(RB);
ok.ok(await md5() === 'c345c799f3d47c41c2dab38d4f31e7a9', 'التراجع يعيد الحي حرفياً');
ok.ok((await one(db, `select to_regclass('public.kwtsms_cap_resets') t`)).t === null, 'التراجع يحذف الجدول');
await db.exec(M);
ok.ok((await one(db, `select to_regclass('public.kwtsms_cap_resets') t`)).t !== null, 'إعادة التطبيق تعمل');
ok.done();
