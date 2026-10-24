// تجربة 20261024120000_descendant_edit_guard على قاعدة محلية معزولة (لا تلمس السيرفر) — قبل/بعد/التراجع:
//   الأب/الجد (عضو) لا يغيّر في سجل قريبه: الوفاة، الأب، الإخفاء، اسم العائلة، الدور، الحالة
//   ولا أي شيء لقريب له حساب دخول؛ تاريخ الوفاة يبقى القديم؛ ابن بلا حساب: الاسم والميلاد والرقم كما هي.
//   المالك/المدير/المراقب، الشخص نفسه، ودوال السيرفر (postgres) لا تتأثر.
// التشغيل: cd supabase/tests/family_links && node descendant_edit_guard.test.mjs
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
const fix = readFileSync(`${REPO}/migrations/20261024120000_descendant_edit_guard.sql`, 'utf8');
const undo = readFileSync(`${REPO}/rollback/20261024120000_descendant_edit_guard_rollback.sql`, 'utf8');

const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const P = { O: id(1), A: id(2), MON: id(3), S: id(5), GF: id(10), F: id(11), SA: id(12), SN: id(13), GS: id(14), X: id(15), SL: id(16), AL: id(17) };
let pass = 0, fail = 0;
const check = (l, ok, x = '') => { ok ? pass++ : fail++; console.log(`${ok ? '✅' : '❌'} ${l}${x ? ' — ' + x : ''}`); };

async function setup(stage) {
  const db = new PGlite();
  await db.exec(baseBody); await db.exec(preFns); await db.exec(baseTriggers);
  if (stage !== 'before') await db.exec(fix);
  if (stage === 'rolledback') await db.exec(undo);
  await db.exec(`
    grant usage on schema auth to authenticated;
    grant select, update on public.profiles to authenticated;
    insert into women_members(id, first_name, gender) values ('${P.GF}', 'جد', 'male'), ('${P.X}', 'غريب', 'male');
    insert into profiles(id, first_name, full_name, gender, role, status, father_id) values
      ('${P.O}', 'مالك', 'المالك', 'male', 'owner', 'active', null),
      ('${P.A}', 'مدير', 'المدير', 'male', 'admin', 'active', null),
      ('${P.MON}', 'مراقب', 'المراقب', 'male', 'monitor', 'active', null),
      ('${P.S}', 'مشرف', 'المشرف', 'male', 'supervisor', 'active', null),
      ('${P.GF}', 'جد', 'الجد', 'male', 'member', 'active', null),
      ('${P.F}', 'أب', 'الأب', 'male', 'member', 'active', '${P.GF}'),
      ('${P.SA}', 'ابن', 'ابن له حساب', 'male', 'admin', 'active', '${P.F}'),
      ('${P.SN}', 'صغير', 'ابن بلا حساب', 'male', 'member', 'active', '${P.F}'),
      ('${P.GS}', 'حفيد', 'حفيد بلا حساب', 'male', 'member', 'active', '${P.SN}'),
      ('${P.SL}', 'مربوط', 'ابن حسابه بمعرّف آخر', 'male', 'member', 'active', '${P.F}'),
      ('${P.X}', 'غريب', 'غريب', 'male', 'member', 'active', null);
    insert into auth.users(id, raw_app_meta_data) values
      ('${P.O}', '{}'), ('${P.A}', '{}'), ('${P.MON}', '{}'), ('${P.S}', '{}'), ('${P.GF}', '{}'), ('${P.F}', '{}'),
      ('${P.SA}', '{}'), ('${P.X}', '{}'), ('${P.AL}', '{"profile_id": "${P.SL}"}');`);
  return db;
}
async function as(db, who, sql, params = []) {
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [JSON.stringify({ sub: who, role: 'authenticated' })]);
  await db.exec('set role authenticated');
  try { return { ok: true, rows: (await db.query(sql, params)).rows }; }
  catch (e) { return { ok: false, err: e.message, hint: e.hint }; }
  finally { await db.exec('reset role'); }
}
const get = async (db, pid) => (await db.query(`select * from profiles where id = $1`, [pid])).rows[0];
const upd = (db, who, pid, set) => as(db, who, `update profiles set ${set} where id = $1`, [pid]);

for (const stage of ['before', 'after', 'rolledback']) {
  const on = stage === 'after';
  console.log(`\n══════ ${{ before: 'قبل التعديل (السيرفر اليوم)', after: 'بعد التعديل', rolledback: 'بعد التراجع' }[stage]} ══════`);
  const db = await setup(stage);

  let r = await upd(db, P.F, P.SA, `is_deceased = true`);
  check(`الأب يسجّل ابنه (له حساب) متوفى: ${on ? 'مرفوض' : 'يمر (الثغرة)'}`, on ? (!r.ok && r.hint === 'descendant_edit_forbidden') : r.ok, r.err ?? '');
  r = await upd(db, P.F, P.SA, `full_name = 'اسم مزوّر'`);
  check(`الأب يغيّر اسم ابنه الذي له حساب: ${on ? 'مرفوض' : 'يمر'}`, on ? (!r.ok && r.hint === 'descendant_has_account') : r.ok, r.err ?? '');
  r = await upd(db, P.F, P.SA, `sort_order = 5`);
  check('الأب يرتّب أبناءه ولو للابن حساب (كما هو)', r.ok, r.err ?? '');
  r = await upd(db, P.F, P.SL, `phone_number = '+96599999999'`);
  check(`حساب مربوط بمعرّف آخر (app_metadata) يُعامل كحساب: ${on ? 'مرفوض' : 'يمر'}`, on ? (!r.ok && r.hint === 'descendant_has_account') : r.ok, r.err ?? '');
  r = await upd(db, P.GF, P.GS, `father_id = '${P.X}'`);
  check(`الجد يغيّر أب حفيده: ${on ? 'مرفوض' : 'يمر'}`, on ? !r.ok : r.ok, r.err ?? '');
  r = await upd(db, P.F, P.SN, `is_hidden_from_tree = true`);
  check(`الأب يخفي ابنه: ${on ? 'مرفوض' : 'يمر'}`, on ? !r.ok : r.ok, r.err ?? '');
  r = await upd(db, P.F, P.SN, `family_name = 'أخرى'`);
  check(`الأب يغيّر اسم عائلة ابنه: ${on ? 'مرفوض' : 'يمر'}`, on ? !r.ok : r.ok, r.err ?? '');

  r = await upd(db, P.F, P.SN, `first_name = 'صغير٢', full_name = 'صغير٢ الأب', birth_date = '2015-01-02', phone_number = '+96550000001', is_deceased = false`);
  let s = await get(db, P.SN);
  check('ابن بلا حساب: الأب يعدّل الاسم والميلاد والرقم (القيم غير المتغيّرة تمر)', r.ok && s.first_name === 'صغير٢' && s.phone_number === '+96550000001', r.err ?? '');
  await db.exec(`update profiles set is_deceased = true, death_date = null where id = '${P.GS}'`);
  r = await upd(db, P.F, P.GS, `death_date = '2026-10-24', first_name = 'حفيد٢'`);
  s = await get(db, P.GS);
  check(`تاريخ وفاة الحفيد ${on ? 'يبقى القديم بصمت والاسم يتغيّر' : 'يتغيّر'}`, r.ok && (on ? s.death_date === null : s.death_date !== null) && s.first_name === 'حفيد٢', r.err ?? `${s.death_date}`);

  r = await upd(db, P.F, P.F, `first_name = 'أب٢'`);
  check('الشخص نفسه يعدّل سجله (كما هو)', r.ok, r.err ?? '');
  for (const [w, n] of [[P.O, 'المالك'], [P.A, 'المدير'], [P.MON, 'المراقب']]) {
    r = await upd(db, w, P.SN, `is_hidden_from_tree = not is_hidden_from_tree`);
    check(`${n} يعدّل سجل أي عضو (كما هو)`, r.ok, r.err ?? '');
  }
  r = await upd(db, P.S, P.SN, `is_deceased = true`);
  check(`المشرف يسجّل وفاة عضو: ${on ? 'مرفوض' : 'يمر (بدون RLS في التجربة)'}`, on ? !r.ok : r.ok, r.err ?? '');
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [JSON.stringify({ sub: P.F, role: 'authenticated' })]);
  r = await db.query(`update profiles set full_name = 'تسلسل من دالة' where id = $1 returning full_name`, [P.SA]).then(x => ({ ok: true }), e => ({ ok: false, err: e.message }));
  check('دوال السيرفر (postgres) تعدّل سجل من له حساب (تسلسل الأسماء، الربط…) كما هي', r.ok, r.err ?? '');
}
console.log(`\n${pass} نجح · ${fail} فشل`);
process.exit(fail ? 1 : 0);
