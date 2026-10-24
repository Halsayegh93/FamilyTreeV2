// تجربة 20261022110000 (جلسات الاستخدام لكل عضو) على قاعدة محلية معزولة — لا تلمس السيرفر.
// التشغيل: cd supabase/tests/family_links && node app_usage_sessions.test.mjs
import { makeDb, as, one, read, counter, P } from './app_config_env.mjs';

const ok = counter();
const mig = read('migrations/20261022110000_app_usage_sessions.sql');
const rb = read('rollback/20261022110000_app_usage_sessions_rollback.sql');

const db = await makeDb();
await db.exec(`
  alter table auth.users add column if not exists last_sign_in_at timestamptz;
  create or replace function public.current_profile_id() returns uuid language sql stable as $$
    select nullif(current_setting('request.jwt.claims', true)::jsonb->>'sub', '')::uuid $$;
  create schema if not exists cron;
`);
await db.exec(mig);

// تسجيل جلسة: عضو مفعّل ✓، مدير ✓، معلّق ✗، مجمّد ✗
const log = (who, secs, screen) => as(db, who, `select public.log_app_session($1, $2)`, [secs, screen]);
ok.ok((await log('M', 120, 'tree')).ok, 'العضو المفعّل يسجّل جلسة');
ok.ok((await log('M', 60, 'tree')).ok, 'تسجيل ثانٍ في نفس اليوم يُجمع');
ok.ok((await log('M', 999999, 'news')).ok, 'الثواني الضخمة تُقصّ عند ساعة');
ok.ok((await log('A', 30, 'admin_today')).ok, 'المدير يسجّل جلسته');
const pend = await log('PEND', 30, 'news');
ok.ok(pend.ok, 'المعلّق لا يخطئ (يُتجاهل بصمت)', pend.err);
const frz = await log('FM', 30, 'news');
ok.ok(frz.ok, 'المجمّد يُتجاهل بصمت', frz.err);
const bad = await log('M', 10, 'Bad Name; drop');
ok.ok(!bad.ok && bad.code === '22023', 'اسم شاشة حر مرفوض', bad.err);
const long = await log('M', 10, 'a'.repeat(41));
ok.ok(!long.ok, 'اسم شاشة أطول من ٤٠ مرفوض');
const anon = await as(db, 'anon', `select public.log_app_session(10, 'tree')`);
ok.ok(!anon.ok, 'الزائر بلا جلسة لا يسجّل');

const row = await one(db, `select sessions, seconds, screens from public.app_usage_member_day where member_id = $1`, [P.M]);
ok.ok(row.sessions === 3 && row.seconds === 120 + 60 + 3600, 'المجموع: الجلسات ٣ والثواني مقصوصة', JSON.stringify(row));
ok.ok(row.screens.tree === 2 && row.screens.news === 1, 'عدّ الشاشات لكل فتح', JSON.stringify(row.screens));
ok.ok((await one(db, `select count(*)::int n from public.app_usage_member_day where member_id = $1`, [P.PEND])).n === 0, 'لا صف للمعلّق');

// القراءة
const own = await as(db, 'O', `select public.app_usage_engagement(7) j`);
ok.ok(own.ok, 'المالك يقرأ المؤشرات', own.err);
const j = own.rows[0].j;
ok.ok(j.daily.length === 1 && j.daily[0].members === 2, 'اليوم: عدد الأعضاء الذين دخلوا = ٢ (العضو والمدير)', JSON.stringify(j.daily));
ok.ok(j.members[0].member_id === P.M && j.members[0].sessions === 3, 'أكثر الأعضاء استخداماً أولاً', JSON.stringify(j.members[0]));
ok.ok(j.screens[0].screen === 'tree' || j.screens[0].screen === 'news', 'قائمة الشاشات تعرض الأكثر فتحاً');
const adm = await as(db, 'A', `select public.app_usage_engagement(30) j`);
ok.ok(adm.ok, 'المدير يقرأ المؤشرات');
for (const who of ['MON', 'S', 'M', 'FA']) {
  const r = await as(db, who, `select public.app_usage_engagement(7) j`);
  ok.ok(!r.ok && r.code === '42501', `${who} لا يقرأ المؤشرات التفصيلية`, r.err);
}
ok.ok(!(await as(db, 'M', `select * from public.app_usage_member_day`)).ok, 'الجدول مقفول عن التطبيقات مباشرة');

// الحفظ ٩٠ يوماً: صف قديم يُحذف عند التسجيل التالي
await db.exec(`insert into public.app_usage_member_day (member_id, day, sessions, seconds) values ('${P.M2}', current_date - 200, 1, 10)`);
await log('M', 10, 'tree');
ok.ok((await one(db, `select count(*)::int n from public.app_usage_member_day where member_id = $1`, [P.M2])).n === 0, 'الصف الأقدم من ٩٠ يوماً يُحذف');

// التراجع
await db.exec(rb);
ok.ok((await one(db, `select count(*)::int n from pg_proc where proname in ('log_app_session','app_usage_engagement')`)).n === 0, 'التراجع يحذف الدوال');
await db.exec(mig);
ok.ok((await one(db, `select count(*)::int n from pg_proc where proname = 'log_app_session'`)).n === 1, 'إعادة التطبيق بعد التراجع تعمل');

ok.done();
