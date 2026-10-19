// تجربة 20261004230000_status_and_phone_guards على قاعدة محلية معزولة (لا تلمس السيرفر) —
// قبل التعديل (الدوال الحية) وبعده وبعد التراجع:
//   ١) فك الرقم (prepare_phone_unlink) لا يفك التجميد
//   ٢) المراقب يفعّل المعلّق فقط — التجميد وفكّه للمالك والمدير
//   ٣) free_phone_for_reregistration لا تحرّر رقم أحد الإدارة أو عضو له حساب دخول
// التشغيل: cd supabase/tests/family_links && node status_and_phone_guards.test.mjs
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
process.on('unhandledRejection', e => { console.log('خطأ:', e.message, e.where ?? '', (e.query ?? '').slice(0, 300)); process.exit(2); });
const REPO = fileURLToPath(new URL('../../', import.meta.url));
const base = readFileSync(new URL('./base.sql', import.meta.url), 'utf8');
const [baseBody, rest] = base.split('-- ─── المشغّلات');
const baseTriggers = rest.slice(rest.indexOf('\n') + 1);
const grab = (src, name) => { const i = src.indexOf(`create or replace function public.${name}(`); return src.slice(i, src.indexOf('$function$;', i) + '$function$;'.length); };
const preFns = ['adopt_tree_profile', 'merge_member_into_tree', 'women_auto_merge_wife']
  .map(n => grab(readFileSync(`${REPO}/rollback/20261001150000_protect_family_links_rollback.sql`, 'utf8'), n)).join('\n\n');
const mig = n => readFileSync(`${REPO}/migrations/${n}.sql`, 'utf8');
const chain = ['20261001150000_protect_family_links', '20261001190000_carry_own_women_node_links'].map(mig);
const fix =readFileSync(`${REPO}/migrations/20261004230000_status_and_phone_guards.sql`, 'utf8');
// ملف التراجع = الدوال الثلاث كما هي على السيرفر الحي اليوم (مطابقة بـ md5(prosrc))
const live = readFileSync(`${REPO}/rollback/20261004230000_status_and_phone_guards_rollback.sql`, 'utf8');

const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const P = {
  O: id(1), A: id(2), MON: id(3), MONF: id(4), S: id(5),
  M1: id(10), M2: id(11), M3: id(12), F1: id(13), F2: id(14), D1: id(15), X1: id(16), XL: id(17),
  PEND: id(20), TM: id(21), NUL: id(22), SELF: id(23), SP: id(24),
  U1: id(40), U2: id(41), U3: id(42), U4: id(43), T1: id(50), A2: id(51), L3: id(52), P4: id(53), Z4: id(54),
};
let pass = 0, fail = 0;
const check = (l, ok, x = '') => { ok ? pass++ : fail++; console.log(`${ok ? '✅' : '❌'} ${l}${x ? ' — ' + x : ''}`); };

async function setup(stage) {
  const db = new PGlite();
  await db.exec(baseBody); await db.exec(preFns); await db.exec(baseTriggers);
  for (const m of chain) await db.exec(m);
  await db.exec(live);
  if (stage !== 'before') await db.exec(fix);
  if (stage === 'rolledback') await db.exec(live);
  await db.exec(`
    grant usage on schema auth to authenticated;
    grant select, update on public.profiles to authenticated;
    grant select, insert on public.notifications to authenticated;
    insert into profiles(id, first_name, full_name, gender, role, status, phone_number) values
      ('${P.O}', 'مالك', 'المالك', 'male', 'owner', 'active', null),
      ('${P.A}', 'بدر', 'مدير', 'male', 'admin', 'active', null),
      ('${P.MON}', 'علي', 'مراقب', 'male', 'monitor', 'active', null),
      ('${P.MONF}', 'فهد', 'مراقب مجمّد', 'male', 'monitor', 'frozen', null),
      ('${P.S}', 'سعد', 'مشرف', 'male', 'supervisor', 'active', null),
      ('${P.M1}', 'أحمد', 'عضو ١', 'male', 'member', 'active', null),
      ('${P.M2}', 'حمد', 'عضو ٢', 'male', 'member', 'active', null),
      ('${P.M3}', 'خالد', 'عضو ٣', 'male', 'member', 'active', null),
      ('${P.F1}', 'مجمّد', 'مجمّد ١', 'male', 'member', 'frozen', '+96590000201'),
      ('${P.F2}', 'مجمّد', 'مجمّد ٢', 'male', 'member', 'frozen', null),
      ('${P.D1}', 'محذوف', 'محذوف ١', 'male', 'member', 'deleted', '+96590000202'),
      ('${P.X1}', 'ناصر', 'مفعّل برقم', 'male', 'member', 'active', '+96590000203'),
      ('${P.PEND}', 'جديد', 'مسجّل معلّق', 'male', 'pending', 'pending', null),
      ('${P.SP}', 'جديد٢', 'مسجّل معلّق ٢', 'male', 'pending', 'pending', null),
      ('${P.TM}', 'شجرة', 'عضو شجرة معلّق', 'male', 'member', 'pending', null),
      ('${P.NUL}', 'بلا', 'بلا حالة', 'male', 'member', null, null),
      ('${P.SELF}', 'نفسه', 'يعيد التسجيل', 'male', 'member', 'active', null),
      ('${P.U1}', '', '', null, 'member', 'pending', '+96590000101'),
      ('${P.U2}', '', '', null, 'member', 'pending', null),
      ('${P.U3}', '', '', null, 'member', 'pending', null),
      ('${P.U4}', '', '', null, 'member', 'pending', null),
      ('${P.T1}', 'شجرة١', 'ملف شجرة بلا حساب', 'male', 'member', 'active', '+96590000111'),
      ('${P.A2}', 'مدير٢', 'مدير برقم', 'male', 'admin', 'active', '+96590000102'),
      ('${P.L3}', 'مربوط', 'عضو له حساب', 'male', 'member', 'active', '+96590000103'),
      ('${P.P4}', 'مربوط٢', 'مربوط بمعرّف آخر', 'male', 'member', 'active', '+96590000104');
    insert into auth.users(id, phone, raw_app_meta_data) values
      ('${P.O}', null, '{}'), ('${P.A}', null, '{}'), ('${P.MON}', null, '{}'), ('${P.MONF}', null, '{}'),
      ('${P.S}', null, '{}'), ('${P.SELF}', null, '{}'), ('${P.X1}', '96590000203', '{}'),
      ('${P.XL}', '96590000203', '{"profile_id": "${P.X1}"}'),
      ('${P.U1}', '96590000111', '{}'), ('${P.U2}', '96590000102', '{}'), ('${P.U3}', '96590000103', '{}'),
      ('${P.U4}', '96590000104', '{}'), ('${P.L3}', '96590000103', '{}'),
      ('${P.Z4}', '96590000999', '{"profile_id": "${P.P4}"}');
    insert into device_tokens(member_id, token) values ('${P.X1}', 'tok-x1-0000000000'), ('${P.F1}', 'tok-f1-0000000000');`);
  return db;
}

async function as(db, who, sql, params = []) {
  const claims = who ? JSON.stringify({ sub: who, role: 'authenticated' }) : '';
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [claims]);
  if (who) await db.exec('set role authenticated');
  try { return { ok: true, rows: (await db.query(sql, params)).rows }; }
  catch (e) { return { ok: false, err: e.message }; }
  finally { if (who) await db.exec('reset role'); }
}
async function asService(db, sql, params = []) {
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [JSON.stringify({ role: 'service_role' })]);
  try { return { ok: true, rows: (await db.query(sql, params)).rows }; }
  catch (e) { return { ok: false, err: e.message }; }
  finally { await db.query(`select set_config('request.jwt.claims', '', false)`); }
}
const row = async (db, pid) => (await db.query(`select status, role, phone_number from profiles where id = $1`, [pid])).rows[0];
const setStatus = (db, who, pid, status, role) => as(db, who,
  role ? `update profiles set status = $2, role = $3 where id = $1` : `update profiles set status = $2 where id = $1`,
  role ? [pid, status, role] : [pid, status]);

for (const stage of ['before', 'after', 'rolledback']) {
  const after = stage === 'after';
  console.log(`\n══════ ${{ before: 'قبل التعديل (السيرفر اليوم)', after: 'بعد التعديل', rolledback: 'بعد التراجع' }[stage]} ══════`);
  const db = await setup(stage);

  console.log('— ١) فك الرقم (prepare_phone_unlink بمفتاح الخدمة):');
  let r = await asService(db, `select public.prepare_phone_unlink($1) as ids`, [P.F1]);
  let x = await row(db, P.F1);
  check(`مجمّد: الرقم يُفك و${after ? 'يبقى مجمّداً' : 'يصير «معلّقاً» (الثغرة)'}`,
    r.ok && x.phone_number === null && x.status === (after ? 'frozen' : 'pending'), r.err ?? `${x.status}`);
  r = await asService(db, `select public.prepare_phone_unlink($1) as ids`, [P.D1]);
  x = await row(db, P.D1);
  check(`محذوف: ${after ? 'يبقى محذوفاً' : 'يصير «معلّقاً»'}`, r.ok && x.status === (after ? 'deleted' : 'pending'), r.err ?? x.status);
  r = await asService(db, `select public.prepare_phone_unlink($1) as ids`, [P.X1]);
  x = await row(db, P.X1);
  const toks = (await db.query(`select count(*)::int as n from device_tokens where member_id = $1`, [P.X1])).rows[0].n;
  check('مفعّل: الرقم يُفك ويصير «معلّقاً» وتُحذف أجهزته وتُرجع حساباته (كما هو)',
    r.ok && x.phone_number === null && x.status === 'pending' && toks === 0 && r.rows[0].ids.length === 2, r.err ?? `${x.status} · أجهزة ${toks}`);
  r = await asService(db, `select public.prepare_phone_unlink($1)`, [P.O]);
  check('المالك محمي (كما هو)', !r.ok && /owner_account_protected/.test(r.err), r.err ?? '');
  r = await as(db, P.A, `select public.prepare_phone_unlink($1)`, [P.M1]);
  check('من غير مفتاح الخدمة مرفوض (كما هو)', !r.ok && /service_only/.test(r.err), r.err ?? '');

  console.log('— ٢) تغيير الحالة (prevent_role_self_promotion):');
  r = await setStatus(db, P.MON, P.M1, 'frozen'); x = await row(db, P.M1);
  check(`المراقب يجمّد عضواً: ${after ? 'مرفوض' : 'يمر (خلاف جدول الأدوار)'}`,
    after ? (!r.ok && /status_change_forbidden/.test(r.err) && x.status === 'active') : (r.ok && x.status === 'frozen'), r.err ?? x.status);
  r = await setStatus(db, P.MON, P.F2, 'active'); x = await row(db, P.F2);
  check(`المراقب يفك تجميد عضو: ${after ? 'مرفوض' : 'يمر (الثغرة)'}`,
    after ? (!r.ok && x.status === 'frozen') : (r.ok && x.status === 'active'), r.err ?? x.status);
  r = await setStatus(db, P.MON, P.M2, 'pending'); x = await row(db, P.M2);
  check(`المراقب يرجّع مفعّلاً «معلّقاً»: ${after ? 'مرفوض' : 'يمر'}`,
    after ? (!r.ok && x.status === 'active') : (r.ok && x.status === 'pending'), r.err ?? x.status);
  r = await setStatus(db, P.MON, P.PEND, 'active', 'member'); x = await row(db, P.PEND);
  check('المراقب يقبل مسجّلاً معلّقاً (معلّق → عضو مفعّل) — كما هو', r.ok && x.status === 'active' && x.role === 'member', r.err ?? '');
  r = await setStatus(db, P.MON, P.TM, 'active'); x = await row(db, P.TM);
  check('المراقب يفعّل عضو شجرة معلّقاً (إضافة رقم/ابن) — كما هو', r.ok && x.status === 'active', r.err ?? '');
  r = await setStatus(db, P.MON, P.NUL, 'active'); x = await row(db, P.NUL);
  check('المراقب يفعّل عضواً بلا حالة — كما هو', r.ok && x.status === 'active', r.err ?? '');
  r = await setStatus(db, P.MON, P.SP, 'frozen'); x = await row(db, P.SP);
  check(`المراقب يجمّد مسجّلاً معلّقاً: ${after ? 'مرفوض' : 'يمر'}`,
    after ? (!r.ok && x.status === 'pending') : (r.ok && x.status === 'frozen'), r.err ?? x.status);
  r = await setStatus(db, P.A, P.M3, 'frozen'); let r2 = await setStatus(db, P.A, P.M3, 'active'); x = await row(db, P.M3);
  check('المدير يجمّد ويفك التجميد — كما هو', r.ok && r2.ok && x.status === 'active', r.err ?? r2.err ?? '');
  r = await setStatus(db, P.O, P.M3, 'frozen'); r2 = await setStatus(db, P.O, P.M3, 'active'); x = await row(db, P.M3);
  check('المالك يجمّد ويفك التجميد — كما هو', r.ok && r2.ok && x.status === 'active', r.err ?? r2.err ?? '');
  r = await setStatus(db, P.S, P.M3, 'frozen'); x = await row(db, P.M3);
  check('المشرف لا يجمّد — كما هو', !r.ok && x.status === 'active', r.err ?? x.status);
  r = await setStatus(db, P.MONF, P.M3, 'frozen'); x = await row(db, P.M3);
  check('مراقب مجمّد لا يغيّر شيئاً — كما هو', !r.ok && /account_inactive/.test(r.err) && x.status === 'active', r.err ?? '');
  r = await setStatus(db, P.SELF, P.SELF, 'pending', 'pending'); x = await row(db, P.SELF);
  check('العضو يعيد تسجيله (مفعّل → معلّق) — كما هو', r.ok && x.status === 'pending' && x.role === 'pending', r.err ?? '');
  r = await setStatus(db, null, P.M3, 'frozen'); x = await row(db, P.M3);
  check('صيانة SQL بلا JWT — كما هي', r.ok && x.status === 'frozen', r.err ?? '');

  console.log('— ٣) تحرير الرقم القديم (free_phone_for_reregistration):');
  const free = (who, phone, member) => as(db, who, `select public.free_phone_for_reregistration($1, $2)`, [phone, member]);
  r = await free(P.U1, '+96590000111', P.U1); x = await row(db, P.T1);
  check('ملف شجرة بلا حساب: يُحرَّر رقمه للمسجّل (كما هو)', r.ok && x.phone_number === null, r.err ?? x.phone_number);
  r = await free(P.U2, '+96590000102', P.U2); x = await row(db, P.A2);
  check(`رقم أحد الإدارة: ${after ? 'مرفوض ويبقى' : 'يُفرَّغ (الثغرة)'}`,
    after ? (!r.ok && /phone_in_use/.test(r.err) && x.phone_number === '+96590000102') : (r.ok && x.phone_number === null), r.err ?? x.phone_number);
  r = await free(P.U3, '+96590000103', P.U3); x = await row(db, P.L3);
  check(`رقم عضو له حساب دخول: ${after ? 'مرفوض ويبقى' : 'يُفرَّغ (الثغرة)'}`,
    after ? (!r.ok && /phone_in_use/.test(r.err) && x.phone_number === '+96590000103') : (r.ok && x.phone_number === null), r.err ?? x.phone_number);
  r = await free(P.U4, '+96590000104', P.U4); x = await row(db, P.P4);
  check(`رقم ملف مربوط بحساب بمعرّف آخر: ${after ? 'مرفوض ويبقى' : 'يُفرَّغ (الثغرة)'}`,
    after ? (!r.ok && /phone_in_use/.test(r.err) && x.phone_number === '+96590000104') : (r.ok && x.phone_number === null), r.err ?? x.phone_number);
  r = await free(P.U1, '+96590000999', P.U1);
  check('رقم غير رقم الدخول مرفوض (كما هو)', !r.ok && /phone_not_verified/.test(r.err), r.err ?? '');
  r = await free(P.U1, '+96590000111', P.U2);
  check('التحرير لسجل غيره مرفوض (كما هو)', !r.ok && /forbidden/.test(r.err), r.err ?? '');
}
console.log(`\nالنتيجة: ${pass} نجح، ${fail} فشل`);
process.exit(fail ? 1 : 0);
