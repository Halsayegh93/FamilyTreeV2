// تجربة 20261128120000_mother_visibility_by_child («ظهور الوالد بجانب الوالدة» و«ظهور الأبناء تحت الوالدة» من حساب
// ابن البنت/بنت البنت حين لا حساب لأمّه، موافقة المالك ٢٠٢٦-١١-٢٨) على قاعدة محلية معزولة (لا تلمس السيرفر):
// قبل الترحيل (لا دالة) ← بعده (الابن/البنت المفعّل يغيّر العمودين فقط على أمّه بلا حساب؛ أمّ لها حساب = mother_has_account؛
// بلا أمّ = no_mother؛ غير مفعّل/مجمّد = not_allowed؛ بلا عقدة = no_node؛ anon بلا تنفيذ) ← بعد التراجع (الدالة حُذفت).
// التشغيل: cd supabase/tests/family_links && node mother_visibility_by_child.test.mjs
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
process.on('unhandledRejection', e => { console.log('خطأ:', e.message, e.where ?? '', (e.query ?? '').slice(0, 300)); process.exit(2); });
const REPO = fileURLToPath(new URL('../../', import.meta.url));
const base = readFileSync(new URL('./base.sql', import.meta.url), 'utf8');
const [baseBody] = base.split('-- ─── المشغّلات');
const MIG = '20261128120000_mother_visibility_by_child';
const mig = readFileSync(`${REPO}/migrations/${MIG}.sql`, 'utf8');
const rb = readFileSync(`${REPO}/rollback/${MIG}_rollback.sql`, 'utf8');

const live = `
alter table public.women_members add column spouse_shown boolean, add column children_shown boolean,
  add column hidden_children uuid[] default '{}'::uuid[], add column is_outside_family boolean default false;
grant usage on schema auth to authenticated, anon;
grant select on all tables in schema public to authenticated;
`;

const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
// F أب (ملف) · M أمّ بلا حساب (زوجها H) · H زوج من خارج العائلة · SP حساب الابن · S عقدته (id = ملفه) ·
// GP حساب البنت · G عقدتها (id غير ملفها، مربوطة بـ linked_user_id) · DP حساب أمّ لها حساب · D عقدتها · K ابنها (حساب KP)
// NP حساب بلا أمّ · N عقدته · ZP مجمّد (عقدته Z تحت M) · PP معلّق (عقدته Q تحت M) · X بلا عقدة
const P = { F: id(1), M: id(2), H: id(3), SP: id(4), S: id(4), GP: id(5), G: id(6), DP: id(7), D: id(8), KP: id(9), K: id(9),
  NP: id(10), N: id(10), ZP: id(11), Z: id(11), PP: id(12), Q: id(12), X: id(13) };
let pass = 0, fail = 0;
const check = (l, ok, x = '') => { ok ? pass++ : fail++; console.log(`${ok ? '✅' : '❌'} ${l}${x ? ' — ' + x : ''}`); };

const db = new PGlite();
await db.exec(baseBody);
await db.exec(live);
await db.exec(`
  insert into profiles(id, first_name, full_name, gender, role, status) values
    ('${P.F}', 'خالد', 'خالد المحمدعلي', 'male', 'member', 'active'),
    ('${P.SP}', 'علي', 'علي حمد', 'male', 'member', 'active'),
    ('${P.GP}', 'نورة', 'نورة حمد', 'female', 'member', 'active'),
    ('${P.DP}', 'سارة', 'سارة خالد', 'female', 'member', 'active'),
    ('${P.KP}', 'يوسف', 'يوسف', 'male', 'member', 'active'),
    ('${P.NP}', 'فهد', 'فهد', 'male', 'member', 'active'),
    ('${P.ZP}', 'بدر', 'بدر حمد', 'male', 'member', 'frozen'),
    ('${P.PP}', 'سعد', 'سعد حمد', 'male', 'pending', 'pending'),
    ('${P.X}', 'ناصر', 'ناصر', 'male', 'member', 'active');
  insert into women_members(id, first_name, full_name, gender) values ('${P.F}', 'خالد', 'خالد المحمدعلي', 'male');
  insert into women_members(id, first_name, full_name, gender, is_outside_family) values ('${P.H}', 'حمد', 'حمد الصالح', 'male', true);
  insert into women_members(id, first_name, full_name, parent_id, husband_id, gender) values
    ('${P.M}', 'مريم', 'مريم خالد', '${P.F}', '${P.H}', 'female');
  insert into women_members(id, first_name, full_name, parent_id, gender, linked_user_id) values
    ('${P.D}', 'سارة', 'سارة خالد', '${P.F}', 'female', '${P.DP}');
  insert into women_members(id, first_name, full_name, parent_id, mother_id, gender, linked_user_id) values
    ('${P.S}', 'علي', 'علي حمد', '${P.H}', '${P.M}', 'male', null),
    ('${P.G}', 'نورة', 'نورة حمد', '${P.H}', '${P.M}', 'female', '${P.GP}'),
    ('${P.K}', 'يوسف', 'يوسف', null, '${P.D}', 'male', null),
    ('${P.Z}', 'بدر', 'بدر حمد', '${P.H}', '${P.M}', 'male', null),
    ('${P.Q}', 'سعد', 'سعد حمد', '${P.H}', '${P.M}', 'male', null);
  insert into women_members(id, first_name, full_name, gender) values ('${P.N}', 'فهد', 'فهد', 'male');
  insert into auth.users(id) values ('${P.SP}'), ('${P.GP}'), ('${P.DP}'), ('${P.KP}'), ('${P.NP}'), ('${P.ZP}'), ('${P.PP}'), ('${P.X}');`);

async function as(who, sql, params = [], role = 'authenticated') {
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [JSON.stringify(who ? { sub: who, role } : { role })]);
  await db.exec(`set role ${role}`);
  try { return { ok: true, rows: (await db.query(sql, params)).rows }; }
  catch (e) { return { ok: false, err: e.message, hint: e.hint }; }
  finally { await db.exec('reset role'); }
}
const call = (who, spouse, children, role) =>
  as(who, `select public.set_mother_visibility($1, $2) r`, [spouse, children], role);
const row = async x => (await db.query(
  `select spouse_shown, children_shown, is_hidden_from_tree, full_name, husband_id from women_members where id = $1`, [x])).rows[0];

// ─── قبل الترحيل ───
const pre = await call(P.SP, true, null);
check('قبل الترحيل: الدالة غير موجودة', !pre.ok && /set_mother_visibility/.test(pre.err), pre.err);

await db.exec(mig);
console.log('\n══════ بعد الترحيل ══════');

const before = await row(P.M);
const s1 = await call(P.SP, true, null);
check('الابن (عقدته = ملفه): يشغّل ظهور الوالد', s1.ok && s1.rows[0].r.spouse === true && s1.rows[0].r.children === false,
  s1.err ?? JSON.stringify(s1.rows?.[0]?.r));
let m = await row(P.M);
check('الأم: spouse_shown = true، children_shown بلا تغيير', m.spouse_shown === true && m.children_shown === null, JSON.stringify(m));
check('الأم: بقية الأعمدة كما هي', m.is_hidden_from_tree === before.is_hidden_from_tree && m.full_name === before.full_name
  && m.husband_id === before.husband_id);

const g1 = await call(P.GP, null, true);
check('البنت (مربوطة بـ linked_user_id): تشغّل ظهور الأبناء', g1.ok && g1.rows[0].r.children === true && g1.rows[0].r.spouse === true,
  g1.err ?? JSON.stringify(g1.rows?.[0]?.r));
const g2 = await call(P.GP, false, false);
m = await row(P.M);
check('إطفاء الاثنين معاً', g2.ok && m.spouse_shown === false && m.children_shown === false, g2.err ?? JSON.stringify(m));
const g3 = await call(P.GP, null, null);
check('بلا قيم: لا تغيير ويرجع الحالي', g3.ok && g3.rows[0].r.spouse === false && g3.rows[0].r.children === false, g3.err);

const k = await call(P.KP, true, true);
check('أمّ لها حساب: مرفوض (mother_has_account)', !k.ok && k.hint === 'mother_has_account', `${k.hint} ${k.err}`);
check('أمّ لها حساب: لا تغيير على عقدتها', (await row(P.D)).spouse_shown === null);

const n = await call(P.NP, true, null);
check('بلا أمّ في الشجرة: مرفوض (no_mother)', !n.ok && n.hint === 'no_mother', `${n.hint} ${n.err}`);
const x = await call(P.X, true, null);
check('بلا عقدة في شجرة النساء: مرفوض (no_node)', !x.ok && x.hint === 'no_node', `${x.hint} ${x.err}`);
const z = await call(P.ZP, true, null);
check('حساب مجمّد: مرفوض (not_allowed)', !z.ok && z.hint === 'not_allowed', `${z.hint} ${z.err}`);
const q = await call(P.PP, true, null);
check('حساب معلّق: مرفوض (not_allowed)', !q.ok && q.hint === 'not_allowed', `${q.hint} ${q.err}`);
m = await row(P.M);
check('بعد الرفض: الأم كما كانت', m.spouse_shown === false && m.children_shown === false, JSON.stringify(m));

const anon = await call(null, true, null, 'anon');
check('anon: لا تنفيذ', !anon.ok && /permission denied/.test(anon.err), anon.err);

const sec = (await db.query(`select prosecdef, proconfig from pg_proc where proname = 'set_mother_visibility'`)).rows[0];
check('SECURITY DEFINER مع search_path ثابت', sec.prosecdef === true && /search_path/.test(String(sec.proconfig)), JSON.stringify(sec));

// ─── التراجع ───
await db.exec(rb);
const gone = (await db.query(`select count(*)::int n from pg_proc where proname = 'set_mother_visibility'`)).rows[0].n;
check('بعد التراجع: الدالة حُذفت', gone === 0);
m = await row(P.M);
check('بعد التراجع: القيم التي اختيرت تبقى', m.spouse_shown === false && m.children_shown === false);

console.log(`\nالنتيجة: ${pass} نجح، ${fail} فشل`);
process.exit(fail ? 1 : 0);
