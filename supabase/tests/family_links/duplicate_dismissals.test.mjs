// تجربة 20261127250000_duplicate_dismissals («ليسا مكرّرين» على السيرفر، موافقة المالك ٢٠٢٦-١١-٢٧) على قاعدة محلية
// معزولة (لا تلمس السيرفر): قبل الترحيل (لا جدول) ← بعده (القراءة والإضافة والحذف للمالك والمدير فقط، المُخفي يُختم
// بمعرّف المتصل، المفتاح مرة واحدة) ← بعد التراجع (لا جدول).
// التشغيل: cd supabase/tests/family_links && node duplicate_dismissals.test.mjs
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
process.on('unhandledRejection', e => { console.log('خطأ:', e.message, (e.query ?? '').slice(0, 300)); process.exit(2); });
const REPO = fileURLToPath(new URL('../../', import.meta.url));
const base = readFileSync(new URL('./base.sql', import.meta.url), 'utf8');
const [baseBody] = base.split('-- ─── المشغّلات');
const MIG = '20261127250000_duplicate_dismissals';
const mig = readFileSync(`${REPO}/migrations/${MIG}.sql`, 'utf8');
const rb = readFileSync(`${REPO}/rollback/${MIG}_rollback.sql`, 'utf8');

const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const P = { O: id(1), ADM: id(2), MON: id(3), MEM: id(4), FRZ: id(5) };
let pass = 0, fail = 0;
const check = (l, ok, x = '') => { ok ? pass++ : fail++; console.log(`${ok ? '✅' : '❌'} ${l}${x ? ' — ' + x : ''}`); };

const db = new PGlite();
await db.exec(baseBody);
await db.exec(`
  grant usage on schema auth to authenticated, anon;
  insert into profiles(id, first_name, role, status) values
    ('${P.O}', 'مالك', 'owner', 'active'), ('${P.ADM}', 'مدير', 'admin', 'active'),
    ('${P.MON}', 'مراقب', 'monitor', 'active'), ('${P.MEM}', 'عضو', 'member', 'active'),
    ('${P.FRZ}', 'مدير موقوف', 'admin', 'frozen');`);

async function as(who, sql, params = []) {
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [JSON.stringify({ sub: who, role: 'authenticated' })]);
  await db.exec('set role authenticated');
  try { return { ok: true, rows: (await db.query(sql, params)).rows }; }
  catch (e) { return { ok: false, err: e.message, code: e.code }; }
  finally { await db.exec('reset role'); }
}
const KEY1 = `${id(9)}|${id(10)},${id(11)}`;
const KEY2 = `${id(9)}|${id(12)},${id(13)}`;

const pre = await as(P.O, `select * from public.duplicate_dismissals`);
check('قبل الترحيل: لا جدول', !pre.ok && /does not exist/.test(pre.err), pre.err);

await db.exec(mig);
console.log('\n══════ بعد الترحيل ══════');

const ins = await as(P.O, `insert into public.duplicate_dismissals(group_key) values ($1) returning dismissed_by, dismissed_at`, [KEY1]);
check('المالك يخفي مجموعة', ins.ok && ins.rows[0].dismissed_by === P.O && ins.rows[0].dismissed_at, ins.err);
const insA = await as(P.ADM, `insert into public.duplicate_dismissals(group_key) values ($1) returning dismissed_by`, [KEY2]);
check('المدير يخفي مجموعة (يُختم بمعرّفه)', insA.ok && insA.rows[0].dismissed_by === P.ADM, insA.err);
const forged = await as(P.ADM, `insert into public.duplicate_dismissals(group_key, dismissed_by) values ('x|y', $1)`, [P.O]);
check('لا يُكتب باسم غيره', !forged.ok, forged.err);
const dup = await as(P.ADM, `insert into public.duplicate_dismissals(group_key) values ($1) on conflict (group_key) do nothing`, [KEY1]);
check('المفتاح نفسه مرة واحدة (إعادة الإخفاء لا تفشل)', dup.ok, dup.err);
const shared = await as(P.ADM, `select group_key from public.duplicate_dismissals order by 1`);
check('المدير يرى ما أخفاه المالك (مشترك)', shared.ok && shared.rows.length === 2, JSON.stringify(shared.rows));

for (const [who, label] of [[P.MON, 'المراقب'], [P.MEM, 'العضو'], [P.FRZ, 'المدير الموقوف']]) {
  const r = await as(who, `select count(*)::int n from public.duplicate_dismissals`);
  check(`${label} لا يقرأ`, (r.ok && r.rows[0].n === 0) || !r.ok, JSON.stringify(r.rows ?? r.err));
  const w = await as(who, `insert into public.duplicate_dismissals(group_key) values ('m|n')`);
  check(`${label} لا يضيف`, !w.ok, w.err);
  const d = await as(who, `delete from public.duplicate_dismissals returning 1`);
  check(`${label} لا يحذف`, !d.ok || d.rows.length === 0);
}
const anonSel = await (async () => {
  await db.exec('set role anon');
  try { await db.query(`select * from public.duplicate_dismissals`); return true; } catch { return false; } finally { await db.exec('reset role'); }
})();
check('غير المسجّل لا يقرأ', anonSel === false);

const del = await as(P.ADM, `delete from public.duplicate_dismissals where group_key = any($1::text[]) returning group_key`, [[KEY1, KEY2]]);
check('«إعادة إظهار ما أخفيته»: المدير يحذف', del.ok && del.rows.length === 2, del.err);
const empty = await as(P.O, `select count(*)::int n from public.duplicate_dismissals`);
check('فرغ الجدول', empty.ok && empty.rows[0].n === 0);
const upd = await as(P.O, `update public.duplicate_dismissals set group_key = 'z'`);
check('لا تعديل (إضافة وحذف فقط)', !upd.ok, upd.err);

await db.exec(rb);
const post = await as(P.O, `select * from public.duplicate_dismissals`);
check('بعد التراجع: لا جدول', !post.ok && /does not exist/.test(post.err), post.err);

console.log(`\nالنتيجة: ${pass} نجح، ${fail} فشل`);
process.exit(fail ? 1 : 0);
