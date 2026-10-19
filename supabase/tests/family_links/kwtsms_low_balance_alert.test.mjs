// تجربة 20261019210000 (تنبيه رصيد KWT SMS) على قاعدة محلية معزولة — لا تلمس السيرفر.
// التشغيل: cd supabase/tests/family_links && node kwtsms_low_balance_alert.test.mjs
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
process.on('unhandledRejection', e => { console.log('خطأ:', e.message, (e.query ?? '').slice(0, 300)); process.exit(2); });
const REPO = fileURLToPath(new URL('../../', import.meta.url));
const base = readFileSync(`${REPO}/migrations/20261019200000_kwtsms_delivery_guard.sql`, 'utf8');
const mig = readFileSync(`${REPO}/migrations/20261019210000_kwtsms_low_balance_alert.sql`, 'utf8');
const rb = readFileSync(`${REPO}/rollback/20261019210000_kwtsms_low_balance_alert_rollback.sql`, 'utf8');
const mig12 = readFileSync(`${REPO}/migrations/20261019230000_kwtsms_urgent_alert_12h.sql`, 'utf8');
const db = new PGlite();
await db.exec(`
do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role; end if;
end $$;
create table public.profiles (id uuid primary key, role text, status text);
create table public.notifications (id uuid primary key default gen_random_uuid(), target_member_id uuid,
  created_by uuid, title text, body text, kind text, is_read boolean default false, created_at timestamptz default now());
create or replace function public.current_user_role() returns text language sql stable as $$
  select nullif(current_setting('test.role', true), '') $$;
`);
await db.exec(base);
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
await db.exec(`insert into public.profiles values ('${id(1)}','owner','active'),('${id(2)}','admin','active'),('${id(3)}','monitor','active'),('${id(4)}','admin','frozen');`);
let pass = 0, fail = 0;
const ok = (c, m) => { if (c) { pass++; console.log('✓', m); } else { fail++; console.log('✗', m); } };
const hex = n => n.toString(16).padStart(64, '0');
let seq = 1;
const send = async (balance, outcome = 'accepted') => {
  const ev = hex(seq++), ph = hex(1000 + seq);
  // حد «٥ بالثانية» العام في reserve: نباعد الأوقات بدل الانتظار
  await db.exec(`update public.kwtsms_deliveries set created_at = created_at - interval '2 seconds'`);
  const r = (await db.query(`select public.reserve_kwtsms_send($1,$2,false) r`, [ev, ph])).rows[0].r;
  if (r !== 'send') throw Error('reserve ' + r);
  await db.query(`select public.finish_kwtsms_send($1,$2,'m1',1,$3)`, [ev, outcome, balance]);
};
const count = async (w = 'true') => Number((await db.query(`select count(*)::int n from public.notifications where ${w}`)).rows[0].n);

// قبل: بلا تنبيه
await send(19);
ok(await count() === 0, 'قبل الترحيل: لا تنبيه');
await db.exec(mig);
await db.exec(mig12);
await send(120); ok(await count() === 0, 'رصيد ١٢٠: لا تنبيه');
await send(45);  ok(await count(`kind='sms_balance_low'`) === 2, 'رصيد ٤٥: تنبيه للمالك والمدير المفعّلين فقط (٢)');
ok(await count(`body like 'باقي 45 نقطة%'`) === 2, 'النص فيه الرصيد');
await send(44);  ok(await count() === 2, 'رصيد ٤٤ بنفس اليوم: ما يتكرر');
await send(9);   ok(await count(`title like 'عاجل%'`) === 2, 'رصيد ٩: تنبيه عاجل رغم تنبيه اليوم');
await send(8);   ok(await count(`title like 'عاجل%'`) === 2, 'رصيد ٨ بعد قليل: ما يتكرر العاجل');
await db.exec(`update public.notifications set created_at = now() - interval '4 hours' where title like 'عاجل%'`);
await send(7);   ok(await count(`title like 'عاجل%'`) === 2, 'بعد ٤ ساعات: ما يتكرر (صار ١٢ ساعة)');
await db.exec(`update public.notifications set created_at = now() - interval '13 hours' where title like 'عاجل%'`);
await send(7);   ok(await count(`title like 'عاجل%'`) === 4, 'بعد ١٣ ساعة: العاجل يتكرر');
const before = await count();
await send(5, 'failed'); ok(await count() === before, 'إرسال فاشل: لا تنبيه');
await db.query(`select public.finish_kwtsms_send($1,'accepted','m9',1,2)`, [hex(999999)]);
ok(await count() === before, 'حدث غير محجوز: لا تنبيه');
// sms_balance_status
await db.exec(`set test.role = 'monitor'`);
let denied = false; try { await db.query(`select public.sms_balance_status()`); } catch { denied = true; }
ok(denied, 'المراقب ما يشوف الرصيد');
await db.exec(`set test.role = 'owner'`);
const st = (await db.query(`select public.sms_balance_status() s`)).rows[0].s;
ok(Number(st.balance) === 7 && st.low === true, 'المالك يشوف آخر رصيد (٧) ومنخفض');
// التراجع
await db.exec(rb);
const b2 = await count(); await send(3); ok(await count() === b2, 'بعد التراجع: بلا تنبيه');
let gone = false; try { await db.query(`select public.sms_balance_status()`); } catch { gone = true; }
ok(gone, 'بعد التراجع: sms_balance_status محذوفة');
console.log(`\n${pass} نجح، ${fail} فشل`);
process.exit(fail ? 1 : 0);
