// تجربة 20261019220000 (مهلة ٥٠ ثانية بدل ٣ دقائق) محلياً — لا تلمس السيرفر.
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
const REPO = fileURLToPath(new URL('../../', import.meta.url));
const r = f => readFileSync(`${REPO}/${f}`, 'utf8');
const db = new PGlite();
await db.exec(`do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role; end if; end $$;`);
await db.exec(r('migrations/20261019200000_kwtsms_delivery_guard.sql'));
let pass = 0, fail = 0; const ok = (c, m) => { if (c) { pass++; console.log('✓', m); } else { fail++; console.log('✗', m); } };
const hex = n => n.toString(16).padStart(64, '0'); let seq = 1;
const reserve = async ph => (await db.query(`select public.reserve_kwtsms_send($1,$2,false) r`, [hex(seq++), hex(ph)])).rows[0].r;
const age = s => db.exec(`update public.kwtsms_deliveries set created_at = created_at - interval '${s} seconds'`);
ok(await reserve(1) === 'send', 'قبل: أول رمز');
await age(70); ok(await reserve(1) === 'blocked', 'قبل: بعد ٧٠ ثانية ممنوع (٣ دقائق)');
await db.exec(r('migrations/20261019220000_kwtsms_cooldown_one_minute.sql'));
ok(await reserve(1) === 'send', 'بعد: بعد ٧٠ ثانية مسموح');
await age(30); ok(await reserve(1) === 'blocked', 'بعد: بعد ٣٠ ثانية ممنوع');
await age(25); ok(await reserve(1) === 'send', 'بعد: بعد ٥٥ ثانية مسموح');
for (let i = 0; i < 3; i++) { await age(55); await reserve(1); }
await age(55); ok(await reserve(1) === 'blocked', 'بعد: الحد ٥ بالساعة لكل رقم باقٍ');
ok(await reserve(2) === 'send', 'رقم ثاني ما يتأثر');
await db.exec(r('rollback/20261019220000_kwtsms_cooldown_one_minute_rollback.sql'));
await age(70); ok(await reserve(3) === 'send' && await (async () => { await age(70); return (await reserve(3)) === 'blocked'; })(), 'بعد التراجع: ٣ دقائق ترجع');
console.log(`\n${pass} نجح، ${fail} فشل`); process.exit(fail ? 1 : 0);
