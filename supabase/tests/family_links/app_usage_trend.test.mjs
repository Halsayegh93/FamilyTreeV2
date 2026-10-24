// تجربة 20261022100000 (مؤشرات استخدام التطبيق اليومية) على قاعدة محلية معزولة — لا تلمس السيرفر.
// التشغيل: cd supabase/tests/family_links && node app_usage_trend.test.mjs
import { makeDb, as, one, val, canExec, read, counter, P, tx } from './app_config_env.mjs';

const ok = counter();
const mig = read('migrations/20261022100000_app_usage_trend.sql');
const rb = read('rollback/20261022100000_app_usage_trend_rollback.sql');

const db = await makeDb();
// cron و device_tokens كما في الحي (updated_at + platform)
await db.exec(`
  alter table public.device_tokens add column if not exists updated_at timestamptz not null default now();
  create schema if not exists cron;
  create table if not exists cron.job (jobid bigserial primary key, schedule text, command text, jobname text unique);
  create or replace function cron.schedule(job_name text, schedule text, command text) returns bigint language sql as $c$
    insert into cron.job (jobname, schedule, command) values (job_name, schedule, command)
    on conflict (jobname) do update set schedule = excluded.schedule, command = excluded.command returning jobid $c$;
  create or replace function cron.unschedule(job_name text) returns boolean language sql as $c$
    delete from cron.job where jobname = job_name returning true $c$;
`);

// بيانات: المالك والمدير والعضو يلهم جهاز، بعضهم دخل قديم
const ago = (h) => `now() - interval '${h} hours'`;
await db.exec(`
  alter table auth.users add column if not exists last_sign_in_at timestamptz;
  update auth.users set phone = null;
  insert into auth.users (id, phone, last_sign_in_at) values
    ('${P.O}', '96590000001', now()), ('${P.A}', '96590000002', ${ago(2)}),
    ('${P.M}', '96590000005', ${ago(24 * 10)}), ('${P.M2}', '96590000006', ${ago(24 * 60)}),
    ('${P.MON}', '96590000003', null), ('${P.FM}', '96590000008', ${ago(1)});
  insert into public.device_tokens (member_id, token, updated_at) values
    ('${P.O}', 'tok-owner-aaaaaaaaaaaaaaaaaaaaaaaa', now()),
    ('${P.A}', 'tok-admin-aaaaaaaaaaaaaaaaaaaaaaa', ${ago(5)}),
    ('${P.M}', 'tok-mem1-aaaaaaaaaaaaaaaaaaaaaaaa', ${ago(24 * 10)}),
    ('${P.M2}', 'tok-mem2-aaaaaaaaaaaaaaaaaaaaaaa', ${ago(24 * 60)}),
    ('${P.FM}', 'tok-frz-aaaaaaaaaaaaaaaaaaaaaaaa', ${ago(1)});
`);

await db.exec(mig);

// «الآن» المعدود: المالك (الآن)، المدير (قبل ٢ ساعة). المجمّد لا يُعدّ (is_moderator غير مؤثّر هنا، الشرط الحالي: ليس مجمّداً)
const before = await one(db, `select public.app_usage_member_total() t, public.app_usage_count_since(now() - interval '1 day') d1`);
ok.ok(before.t === 5 || before.t === 4, 'إجمالي الفعّالين بالتعريف (رقم + جهاز + غير مجمّد)', JSON.stringify(before));
ok.ok(Number(before.d1) >= 2, 'آخر ٢٤ ساعة تحسب المالك والمدير', JSON.stringify(before));

// لقطة اليوم المنتهي ← صف واحد ثم تكرار يحدّث بدل أن يكرر
await db.exec(`select public.record_app_usage_day(), public.record_app_usage_day()`);
const rows = await one(db, `select count(*)::int n from public.app_usage_daily`);
ok.ok(rows.n === 1, 'اللقطة لليوم المنتهي مرة واحدة حتى لو سُجّلت مرتين');
const snap = await one(db, `select active_1d, active_7d, active_30d, members from public.app_usage_daily`);
ok.ok(snap.active_7d >= snap.active_1d && snap.active_30d >= snap.active_7d, 'النوافذ متداخلة: ١ ≤ ٧ ≤ ٣٠', JSON.stringify(snap));

// القراءة: المالك والمدير فقط
const own = await as(db, 'O', `select public.app_usage_trend(7) j`);
ok.ok(own.ok && own.rows[0].j.today.live === true, 'المالك يقرأ الاتجاه واليوم الحالي مباشرة', own.err);
const adm = await as(db, 'A', `select public.app_usage_trend(30) j`);
ok.ok(adm.ok, 'المدير يقرأ الاتجاه');
const j = adm.rows[0].j;
ok.ok(j.days === 30 && Array.isArray(j.history) && j.history.length === 1, 'السجل يرجع اللقطات الماضية فقط', JSON.stringify(j.history).slice(0, 120));
for (const who of ['MON', 'S', 'M', 'FA']) {
  const r = await as(db, who, `select public.app_usage_trend(7) j`);
  ok.ok(!r.ok && r.code === '42501', `${who} لا يقرأ المؤشرات`, r.err);
}
const anon = await as(db, 'anon', `select public.app_usage_trend(7)`);
ok.ok(!anon.ok, 'الزائر بلا جلسة لا يقرأ المؤشرات');
const days = await as(db, 'O', `select public.app_usage_trend(500) j`);
ok.ok(days.rows[0].j.days === 90, 'المدى يُقصّ عند ٩٠ يوماً');

// الجدول مقفول عن التطبيقات
ok.ok(!(await canExec(db, 'authenticated', 'public.record_app_usage_day()')), 'تسجيل اللقطة للمهمة فقط (ليس للتطبيقات)');
ok.ok(!(await canExec(db, 'authenticated', 'public.app_usage_count_since(timestamptz)')), 'العدّ الداخلي غير متاح للتطبيقات');
const tbl = await as(db, 'O', `select * from public.app_usage_daily`);
ok.ok(!tbl.ok, 'الجدول نفسه لا يُقرأ مباشرة من التطبيق');

// الجدولة
const job = await one(db, `select schedule from cron.job where jobname = 'app-usage-daily'`);
ok.ok(job && job.schedule === '0 21 * * *', 'المهمة ٢١:٠٠ UTC = ٠٠:٠٠ الكويت');

// التراجع يعيد الحالة
await db.exec(rb);
ok.ok((await one(db, `select count(*)::int n from pg_proc where proname = 'app_usage_trend'`)).n === 0, 'التراجع يحذف الدالة');
ok.ok((await one(db, `select count(*)::int n from cron.job where jobname = 'app-usage-daily'`)).n === 0, 'التراجع يلغي المهمة');
await db.exec(mig);
ok.ok((await one(db, `select count(*)::int n from pg_proc where proname = 'app_usage_trend'`)).n === 1, 'إعادة التطبيق بعد التراجع تعمل');

ok.done();
