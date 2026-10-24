// تجربة 20261023100000 (حماية طلبات رمز الدخول) على قاعدة محلية معزولة — لا تلمس السيرفر.
// التشغيل: cd supabase/tests/family_links && node kwtsms_request_lock.test.mjs
import { makeDb, one, read, counter, mig, P } from './app_config_env.mjs';

const ok = counter();
const M = read('migrations/20261023100000_kwtsms_request_lock.sql');
const RB = read('rollback/20261023100000_kwtsms_request_lock_rollback.sql');
const db = await makeDb();
await db.exec(mig('config'));
await db.exec(`
  alter table public.app_settings add column if not exists sms_per_number_hour int default 3,
    add column if not exists sms_all_hour int default 100, add column if not exists sms_sender text;
  update public.app_settings set sms_wait_seconds = 60, sms_per_number_hour = 3;
  create table public.kwtsms_deliveries (event_hash text primary key, phone_hash text not null,
    created_at timestamptz not null default clock_timestamp(), test_mode boolean not null,
    outcome text not null default 'pending', provider_msgid text, points_charged numeric, balance_after numeric);
  create table if not exists public.notifications (id uuid primary key default gen_random_uuid(), target_member_id uuid,
    title text, body text, kind text, created_by uuid, is_read boolean default false, created_at timestamptz default now());
`);
// الدالة الحية كما هي (من ملف التراجع) ثم الترحيل
const liveDef = RB.slice(RB.indexOf('CREATE OR REPLACE FUNCTION'), RB.indexOf('$function$;') + '$function$;'.length);
await db.exec(liveDef);
const md5Live = (await one(db, `select md5(pg_get_functiondef('public.reserve_kwtsms_send(text,text,boolean,integer)'::regprocedure)) m`)).m;
ok.ok(md5Live === 'ada5bf5d78f92c51a28ca8dd0e138292', 'ملف التراجع = الدالة الحية حرفياً', md5Live);
await db.exec(M);

const hex = (n) => n.toString(16).padStart(64, '0');
let ev = 1;
const reserve = async (phone) => (await one(db, `select public.reserve_kwtsms_send($1, $2, false, 2) r`, [hex(1000 + ev++), phone])).r;
const A = hex(1), B = hex(2);
const age = (secs) => db.exec(`update public.kwtsms_deliveries set created_at = created_at - interval '${secs} seconds';
  update public.kwtsms_request_log set created_at = created_at - interval '${secs} seconds';
  update public.kwtsms_number_locks set locked_until = locked_until - interval '${secs} seconds', locked_at = locked_at - interval '${secs} seconds';`);

// أول طلب يُرسل، والتالي ينتظر الدقيقة كما كان
ok.ok((await reserve(A)).startsWith('send'), 'الطلب الأول يُرسل');
ok.ok((await reserve(A)).startsWith('blocked:'), 'الطلب الثاني ينتظر (الحماية القديمة)');
// ٦ طلبات خلال ١٠ دقائق ← قفل
for (let i = 0; i < 3; i++) await reserve(A);
const r6 = await reserve(A);
const secs = Number(r6.split(':')[1]);
ok.ok(r6.startsWith('blocked:') && secs > 1700 && secs <= 1800, 'الطلب السادس يقفل الرقم ٣٠ دقيقة', r6);
ok.ok((await one(db, `select count(*)::int n from public.kwtsms_number_locks where phone_hash = $1`, [A])).n === 1, 'سجل القفل محفوظ');
const notes = (await one(db, `select count(*)::int n, max(kind) k from public.notifications where target_member_id = $1`, [P.O]));
ok.ok(notes.n === 1 && notes.k === 'sms_suspicious', 'إشعار واحد للمالك عند القفل', JSON.stringify(notes));
ok.ok((await one(db, `select count(*)::int n from public.notifications where target_member_id = $1`, [P.A])).n === 0, 'المدير ما يوصله إشعار القفل');
// بعد ٥ دقائق: ما زال مقفولاً حتى لو انتهت مهلة الدقيقة
await age(300);
ok.ok((await reserve(A)).startsWith('blocked:'), 'بعد ٥ دقائق ما زال مقفولاً');
ok.ok((await one(db, `select count(*)::int n from public.notifications`)).n === 1, 'لا إشعار ثانٍ أثناء القفل نفسه');
// رقم آخر لا يتأثر
ok.ok((await reserve(B)).startsWith('send'), 'رقم آخر يُرسل عادي');
// بعد انتهاء القفل والنافذة: يُرسل
await age(3600);
ok.ok((await reserve(A)).startsWith('send'), 'بعد انتهاء القفل يرجع يُرسل');

// الحد اليومي: ٦ رسائل خلال ٢٤ ساعة
const C = hex(3);
await db.exec(`update public.app_settings set sms_per_number_hour = 20`);
for (let i = 0; i < 6; i++) { ok.ok((await reserve(C)).startsWith('send'), `رسالة ${i + 1} من ٦ في اليوم`); await age(700); }
const r7 = await reserve(C);
ok.ok(r7.startsWith('blocked:') && Number(r7.split(':')[1]) > 3600, 'الرسالة السابعة في اليوم ترفض لساعات', r7);

// القيم من «قيم التطبيق»
await db.exec(`update public.app_config set value = '3' where key = 'sms_lock_requests'`);
const D = hex(4);
await reserve(D); await reserve(D);
ok.ok(Number((await reserve(D)).split(':')[1]) > 1700, 'تغيير الحد إلى ٣ طلبات يسري فوراً');

// الصلاحيات
for (const r of ['anon', 'authenticated']) {
  ok.ok(!(await one(db, `select has_table_privilege('${r}', 'public.kwtsms_request_log', 'select') x`)).x, `سجل الطلبات مقفول عن ${r}`);
  ok.ok(!(await one(db, `select has_table_privilege('${r}', 'public.kwtsms_number_locks', 'select') x`)).x, `جدول القفل مقفول عن ${r}`);
}

// التراجع يعيد الحي حرفياً
await db.exec(RB);
ok.ok((await one(db, `select md5(pg_get_functiondef('public.reserve_kwtsms_send(text,text,boolean,integer)'::regprocedure)) m`)).m === 'ada5bf5d78f92c51a28ca8dd0e138292', 'التراجع يعيد الدالة الحية حرفياً');
ok.ok((await one(db, `select to_regclass('public.kwtsms_number_locks') is null x`)).x, 'التراجع يحذف الجداول');
await db.exec(M);
ok.ok((await reserve(hex(9))).startsWith('send'), 'إعادة التطبيق بعد التراجع تعمل');
ok.done();
