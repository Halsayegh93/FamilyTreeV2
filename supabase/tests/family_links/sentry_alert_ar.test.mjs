// تجربة 20261127140000 (تنبيه الأخطاء بالعربي) على قاعدة محلية معزولة — لا تلمس السيرفر.
// التشغيل: cd supabase/tests/family_links && node sentry_alert_ar.test.mjs
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
process.on('unhandledRejection', e => { console.log('خطأ:', e.message); process.exit(2); });
const REPO = fileURLToPath(new URL('../../', import.meta.url));
const mig = readFileSync(`${REPO}/migrations/20261127140000_sentry_alert_ar.sql`, 'utf8');
const rb = readFileSync(`${REPO}/rollback/20261127140000_sentry_alert_ar_rollback.sql`, 'utf8');
const db = new PGlite();
await db.exec(`
do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role; end if;
end $$;
create schema if not exists private;
create table public.profiles (id uuid primary key, role text, status text);
create table public.notifications (id uuid primary key default gen_random_uuid(), target_member_id uuid,
  created_by uuid, title text, body text, kind text, is_read boolean default false, created_at timestamptz default now());
`);
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
await db.exec(`insert into public.profiles values ('${id(1)}','owner','active'),('${id(2)}','owner','active'),
  ('${id(3)}','admin','active'),('${id(4)}','owner','frozen'),('${id(5)}','member','active');`);
await db.exec(mig);
let pass = 0, fail = 0;
const ok = (c, m) => { if (c) { pass++; console.log('✓', m); } else { fail++; console.log('✗', m); } };
const claim = async (i, h = 6) => (await db.query(`select public.sentry_alert_claim($1,$2) c`, [i, h])).rows[0].c;

ok(await claim('6012345678') === true, 'أول مرة: يرسل');
ok(await claim('6012345678') === false, 'نفس الخطأ فوراً: لا يرسل');
ok(await claim('6012345679') === true, 'خطأ آخر: يرسل');
await db.exec(`update private.sentry_alert_log set last_sent_at = now() - interval '5 hours' where issue_id='6012345678'`);
ok(await claim('6012345678') === false, 'بعد ٥ ساعات: لا يرسل');
await db.exec(`update private.sentry_alert_log set last_sent_at = now() - interval '6 hours 1 minute' where issue_id='6012345678'`);
ok(await claim('6012345678') === true, 'بعد ٦ ساعات: يرسل');
const cnt = (await db.query(`select sent_count from private.sentry_alert_log where issue_id='6012345678'`)).rows[0].sent_count;
ok(cnt === 2, 'العدّاد ٢');
await db.query(`select public.sentry_alert_release('6012345678')`);
ok(await claim('6012345678') === true, 'بعد فشل الإرسال (release): يرسل في النداء التالي');
let bad = false; try { await claim("1; drop table x"); } catch { bad = true; }
ok(bad, 'رقم خطأ غير صالح: يُرفض');
await db.exec(`insert into private.sentry_alert_log values ('1', now() - interval '91 days', 1)`);
await claim('6012345690');
ok((await db.query(`select count(*)::int n from private.sentry_alert_log where issue_id='1'`)).rows[0].n === 0, 'تنظيف ما مضى عليه ٩٠ يوماً');

const n = (await db.query(`select public.sentry_alert_notify_owners('خطأ في آيفون: توقّف التطبيق فجأة','قراءة من ذاكرة غير صالحة · 12 مرة') n`)).rows[0].n;
ok(n === 2, 'الإشعار للمالكَين المفعّلَين فقط (٢)');
const rows = (await db.query(`select target_member_id t, kind from public.notifications order by t`)).rows;
ok(rows.every(r => r.kind === 'app_error') && rows.map(r => r.t).join() === [id(1), id(2)].join(), 'النوع app_error ولا يصل المدير ولا المجمّد');

// الصلاحيات: التطبيقات لا تنادي
for (const role of ['authenticated', 'anon']) {
  let denied = false;
  try { await db.exec(`set role ${role}; select public.sentry_alert_claim('5');`); } catch { denied = true; }
  await db.exec('reset role');
  ok(denied, `${role} ما ينادي sentry_alert_claim`);
  denied = false;
  try { await db.exec(`set role ${role}; select public.sentry_alert_notify_owners('x','y');`); } catch { denied = true; }
  await db.exec('reset role');
  ok(denied, `${role} ما ينادي sentry_alert_notify_owners`);
}
// التراجع
await db.exec(rb);
let gone = false; try { await claim('7'); } catch { gone = true; }
ok(gone, 'بعد التراجع: الدالة محذوفة');
ok((await db.query(`select to_regclass('private.sentry_alert_log') r`)).rows[0].r === null, 'بعد التراجع: الجدول محذوف');
console.log(`\n${pass} نجح، ${fail} فشل`);
process.exit(fail ? 1 : 0);
