// تجربة 20261023130000 («رمز واحد») — قاعدة محلية معزولة: الحية (lock) ثم الترحيل.
import { makeDb, one, read, counter, mig } from './app_config_env.mjs';
const ok = counter();
const M = read('migrations/20261023130000_kwtsms_one_code.sql');
const RB = read('rollback/20261023130000_kwtsms_one_code_rollback.sql');
const LOCK = read('migrations/20261023100000_kwtsms_request_lock.sql');
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
// الحالة الحية: ترحيل القفل ثم الدالة الحية من ملف التراجع
await db.exec(LOCK);
await db.exec(RB.slice(RB.indexOf('CREATE OR REPLACE FUNCTION'), RB.indexOf('$function$;') + 11));
ok.ok((await one(db, `select md5(pg_get_functiondef('public.reserve_kwtsms_send(text,text,boolean,integer)'::regprocedure)) m`)).m === 'c536b10d0a1013d5e0d18dae164d80db', 'ملف التراجع = الحي');
await db.exec(M);
const hex = n => n.toString(16).padStart(64, '0'); let ev = 1;
const reserve = p => one(db, `select public.reserve_kwtsms_send($1,$2,false,2) r`, [hex(5000 + ev++), p]).then(x => x.r);
const age = s => db.exec(`update public.kwtsms_deliveries set created_at = created_at - interval '${s} seconds'; update public.kwtsms_request_log set created_at = created_at - interval '${s} seconds'`);
const A = hex(1);
ok.ok((await reserve(A)).startsWith('send'), 'الطلب الأول يُرسل');
await age(90);
const r = await reserve(A); const secs = Number(r.split(':')[1]);
ok.ok(r.startsWith('blocked:') && secs > 180 && secs <= 210, 'إعادة الإرسال بعد ٩٠ ث تُرفض حتى تنتهي الخمس دقائق', r);
await age(220);
ok.ok((await reserve(A)).startsWith('send'), 'بعد انتهاء صلاحية الرمز يُرسل');
await db.exec(`update public.app_config set value = '0' where key = 'sms_one_code_seconds'`);
const B = hex(2); await reserve(B); await age(70);
ok.ok((await reserve(B)).startsWith('send'), 'القيمة ٠ تطفئها (ترجع مهلة الدقيقة)');
await db.exec(RB);
ok.ok((await one(db, `select md5(pg_get_functiondef('public.reserve_kwtsms_send(text,text,boolean,integer)'::regprocedure)) m`)).m === 'c536b10d0a1013d5e0d18dae164d80db', 'التراجع يعيد الحي حرفياً');
ok.done();
