// تجربة 20261024140000_add_or_link_self_relative على قاعدة محلية معزولة (لا تلمس السيرفر):
//   الزوجة/الأم من بنات أب في الشجرة — ربط بنت موجودة أو إضافتها تحته، للعضو المفعّل عن نفسه، ثم التراجع.
// التشغيل: cd supabase/tests/family_links && node add_or_link_self_relative.test.mjs
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
process.on('unhandledRejection', e => { console.log('خطأ:', e.message); process.exit(2); });
const REPO = fileURLToPath(new URL('../../', import.meta.url));
const base = readFileSync(new URL('./base.sql', import.meta.url), 'utf8');
const [baseBody, rest] = base.split('-- ─── المشغّلات');
const baseTriggers = rest.slice(rest.indexOf('\n') + 1);
const grab = (src, name) => { const i = src.indexOf(`create or replace function public.${name}(`); return src.slice(i, src.indexOf('$function$;', i) + '$function$;'.length); };
const preFns = ['adopt_tree_profile', 'merge_member_into_tree', 'women_auto_merge_wife']
  .map(n => grab(readFileSync(`${REPO}/rollback/20261001150000_protect_family_links_rollback.sql`, 'utf8'), n)).join('\n\n');
const fix = readFileSync(`${REPO}/migrations/20261024140000_add_or_link_self_relative.sql`, 'utf8');
const undo = readFileSync(`${REPO}/rollback/20261024140000_add_or_link_self_relative_rollback.sql`, 'utf8');

const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
// GF جد · F أبو المتصل · ME المتصل · X رجل آخر (أبو البنات) · D1 بنت X عزباء · D2 بنت X متزوجة · FR مجمّد
const P = { GF: id(1), F: id(2), ME: id(3), X: id(4), Y: id(5), D1: id(10), D2: id(11), FR: id(6), NOF: id(7) };
let pass = 0, fail = 0;
const check = (l, ok, x = '') => { ok ? pass++ : fail++; console.log(`${ok ? '✅' : '❌'} ${l}${x ? ' — ' + x : ''}`); };

const db = new PGlite();
await db.exec(baseBody); await db.exec(preFns); await db.exec(baseTriggers);
await db.exec(`
  grant usage on schema auth to authenticated;
  grant select on all tables in schema public to authenticated;
  insert into women_members(id, first_name, full_name, gender) values ('${P.Y}', 'زوج', 'زوج', 'male');
  insert into profiles(id, first_name, full_name, gender, role, status, father_id) values
    ('${P.GF}', 'جد', 'جد المحمدعلي', 'male', 'member', 'active', null);
  insert into women_members(id, first_name, full_name, gender) values ('${P.GF}', 'جد', 'جد المحمدعلي', 'male');
  insert into profiles(id, first_name, full_name, gender, role, status, father_id) values
    ('${P.F}', 'أب', 'أب جد المحمدعلي', 'male', 'member', 'active', '${P.GF}'),
    ('${P.X}', 'خالد', 'خالد جد المحمدعلي', 'male', 'member', 'active', '${P.GF}'),
    ('${P.ME}', 'أحمد', 'أحمد أب جد المحمدعلي', 'male', 'member', 'active', '${P.F}'),
    ('${P.FR}', 'مجمّد', 'مجمّد أب', 'male', 'member', 'frozen', '${P.F}'),
    ('${P.NOF}', 'بلا', 'بلا أب', 'male', 'member', 'active', null);
  insert into auth.users(id) values ('${P.ME}'), ('${P.FR}'), ('${P.NOF}');
  insert into women_members(id, first_name, full_name, parent_id, gender, husband_id) values
    ('${P.D1}', 'سارة', 'سارة خالد', '${P.X}', 'female', null),
    ('${P.D2}', 'نورة', 'نورة خالد', '${P.X}', 'female', '${P.Y}');
  insert into women_members(id, first_name, full_name, gender) values ('${P.NOF}', 'بلا', 'بلا أب', 'male') on conflict do nothing;`);

async function as(who, sql, params = []) {
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [JSON.stringify({ sub: who, role: 'authenticated' })]);
  await db.exec('set role authenticated');
  try { return { ok: true, rows: (await db.query(sql, params)).rows }; }
  catch (e) { return { ok: false, err: e.message, hint: e.hint }; }
  finally { await db.exec('reset role'); }
}
const call = (who, kind, father, woman, name) =>
  as(who, `select public.add_or_link_self_relative($1, $2, $3, $4) as id`, [kind, father, woman, name]);
const w = async (wid) => (await db.query(`select * from women_members where id = $1`, [wid])).rows[0];

console.log('\n══════ قبل الإضافة ══════');
let r = await call(P.ME, 'wife', P.X, P.D1, null);
check('الدالة غير موجودة قبل الإضافة', !r.ok);

await db.exec(fix);
console.log('\n══════ بعد الإضافة ══════');
r = await call(P.ME, 'wife', P.X, P.D1, null);
check('زوجة: ربط بنت عزباء لأب في الشجرة', r.ok && (await w(P.D1)).husband_id === P.ME, r.err ?? '');
r = await call(P.ME, 'wife', P.X, P.D2, null);
check('زوجة: بنت متزوجة من غيره مرفوضة', !r.ok && r.hint === 'already_married', r.hint ?? '');
r = await call(P.ME, 'wife', P.X, null, 'هند');
let nw = r.ok ? await w(r.rows[0].id) : null;
check('زوجة: بنت جديدة تُضاف تحت أبيها باسمها + سلسلة الأب', r.ok && nw.parent_id === P.X && nw.husband_id === P.ME && nw.full_name === 'هند خالد جد المحمدعلي', r.err ?? nw?.full_name);
r = await call(P.ME, 'mother', P.X, null, 'فاطمة');
let mo = r.ok ? await w(r.rows[0].id) : null;
const meNode = await w(P.ME);
check('أم: بنت جديدة تحت أبيها، زوجة أبي المتصل، وأمه', r.ok && mo.parent_id === P.X && mo.husband_id === P.F && meNode.mother_id === mo.id, r.err ?? '');
r = await call(P.ME, 'sister', P.F, null, 'مريم');
let si = r.ok ? await w(r.rows[0].id) : null;
check('أخت: بنت جديدة تحت أبي المتصل، بلا زوج', r.ok && si.parent_id === P.F && si.husband_id === null && si.full_name === 'مريم أب جد المحمدعلي', r.err ?? si?.full_name);
r = await call(P.ME, 'sister', P.X, null, 'مريم');
check('أخت تحت رجل غير أبيه مرفوضة', !r.ok && r.hint === 'not_daughter', r.hint ?? '');
r = await call(P.ME, 'wife', P.ME, null, 'x');
check('الأب = المتصل نفسه مرفوض', !r.ok && r.hint === 'no_father', r.hint ?? '');
r = await call(P.ME, 'wife', P.GF, P.D2, null);
check('بنت ليست من بنات الأب المختار مرفوضة', !r.ok && r.hint === 'not_daughter', r.hint ?? '');
r = await call(P.ME, 'wife', P.X, null, '  ');
check('بلا اسم مرفوض', !r.ok && r.hint === 'name_required', r.hint ?? '');
r = await call(P.ME, 'cousin', P.X, null, 'x');
check('نوع غير معروف مرفوض', !r.ok && r.hint === 'bad_kind', r.hint ?? '');
r = await call(P.FR, 'wife', P.X, null, 'x');
check('الحساب المجمّد مرفوض', !r.ok && r.hint === 'not_allowed', r.hint ?? '');
r = await call(P.NOF, 'mother', P.X, null, 'x');
check('أم لمن ليس له أب في الشجرة مرفوضة', !r.ok && r.hint === 'no_own_father', r.hint ?? '');

await db.exec(undo);
console.log('\n══════ بعد التراجع ══════');
r = await call(P.ME, 'wife', P.X, null, 'y');
check('الدالة حُذفت', !r.ok);

console.log(`\n${pass} نجح · ${fail} فشل`);
process.exit(fail ? 1 : 0);
