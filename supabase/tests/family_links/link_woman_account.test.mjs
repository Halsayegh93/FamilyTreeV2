// تجربة 20261024181856_link_woman_account على قاعدة محلية معزولة (لا تلمس السيرفر):
//   دخول النساء — ربط طلب انضمام أنثى بعقدتها في شجرة النساء (أو عقدة جديدة تحت أبيها) وتفعيل حسابها، ثم التراجع.
// التشغيل: cd supabase/tests/family_links && node link_woman_account.test.mjs
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
const fix = readFileSync(`${REPO}/migrations/20261024181856_link_woman_account.sql`, 'utf8');
const undo = readFileSync(`${REPO}/rollback/20261024181856_link_woman_account_rollback.sql`, 'utf8');

const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
// O مالك · MON مراقب · S مشرف · M عضو · F أب في الشجرة · W1 بنت F بلا حساب · W2 بنت مربوطة بحساب آخر
// A1/A2/A3 حسابات نساء بطلب انضمام · AM حساب ذكر بطلب · AF أنثى لها أب في شجرة الرجال
const P = { O: id(1), MON: id(2), S: id(3), M: id(4), F: id(5), W1: id(10), W2: id(11),
  A1: id(20), A2: id(21), A3: id(22), AM: id(23), AF: id(24), X: id(25) };
const R = { r1: id(101), r2: id(102), r3: id(103), rm: id(104), rf: id(105), rdone: id(106) };
let pass = 0, fail = 0;
const check = (l, ok, x = '') => { ok ? pass++ : fail++; console.log(`${ok ? '✅' : '❌'} ${l}${x ? ' — ' + x : ''}`); };

const db = new PGlite();
await db.exec(baseBody); await db.exec(preFns); await db.exec(baseTriggers);
await db.exec(`
  alter table public.admin_requests add column if not exists replied_by uuid, add column if not exists replied_at timestamptz;
  grant usage on schema auth to authenticated;
  grant select on all tables in schema public to authenticated;
  insert into profiles(id, first_name, full_name, gender, role, status, father_id) values
    ('${P.F}', 'خالد', 'خالد المحمدعلي', 'male', 'member', 'active', null);
  insert into women_members(id, first_name, full_name, gender) values ('${P.F}', 'خالد', 'خالد المحمدعلي', 'male') on conflict do nothing;
  insert into profiles(id, first_name, full_name, gender, role, status, father_id, is_phone_hidden, is_hidden_from_tree) values
    ('${P.O}', 'مالك', 'المالك', 'male', 'owner', 'active', null, false, false),
    ('${P.MON}', 'مراقب', 'المراقب', 'male', 'monitor', 'active', null, false, false),
    ('${P.S}', 'مشرف', 'المشرف', 'male', 'supervisor', 'active', null, false, false),
    ('${P.M}', 'عضو', 'عضو', 'male', 'member', 'active', null, false, false),
    ('${P.X}', 'آخر', 'حساب آخر', 'female', 'member', 'active', null, true, true),
    ('${P.A1}', 'سارة', 'سارة خالد', 'female', 'pending', 'pending', null, false, false),
    ('${P.A2}', 'هند', 'هند خالد', 'female', 'pending', 'pending', null, false, false),
    ('${P.A3}', 'مها', 'مها خالد', 'female', 'pending', 'pending', null, false, false),
    ('${P.AM}', 'علي', 'علي خالد', 'male', 'pending', 'pending', null, false, false),
    ('${P.AF}', 'ريم', 'ريم خالد', 'female', 'member', 'pending', '${P.F}', false, false);
  insert into women_members(id, first_name, full_name, parent_id, gender, linked_user_id) values
    ('${P.W1}', 'سارة', 'سارة خالد المحمدعلي', '${P.F}', 'female', null),
    ('${P.W2}', 'نورة', 'نورة خالد المحمدعلي', '${P.F}', 'female', '${P.X}');
  insert into admin_requests(id, member_id, requester_id, request_type, status) values
    ('${R.r1}', '${P.A1}', '${P.A1}', 'join_request', 'pending'),
    ('${R.r2}', '${P.A2}', '${P.A2}', 'join_request', 'pending'),
    ('${R.r3}', '${P.A3}', '${P.A3}', 'link_request', 'pending'),
    ('${R.rm}', '${P.AM}', '${P.AM}', 'join_request', 'pending'),
    ('${R.rf}', '${P.AF}', '${P.AF}', 'join_request', 'pending'),
    ('${R.rdone}', '${P.A3}', '${P.A3}', 'join_request', 'approved');
  insert into auth.users(id) values ('${P.O}'), ('${P.MON}'), ('${P.S}'), ('${P.M}');`);

async function as(who, sql, params = []) {
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [JSON.stringify({ sub: who, role: 'authenticated' })]);
  await db.exec('set role authenticated');
  try { return { ok: true, rows: (await db.query(sql, params)).rows }; }
  catch (e) { return { ok: false, err: e.message, hint: e.hint }; }
  finally { await db.exec('reset role'); }
}
const link = (who, req, woman, father, name) =>
  as(who, `select public.link_woman_account($1, $2, $3, $4) as id`, [req, woman, father, name]);
const prof = async (pid) => (await db.query(`select * from profiles where id = $1`, [pid])).rows[0];
const node = async (wid) => (await db.query(`select * from women_members where id = $1`, [wid])).rows[0];
const req = async (rid) => (await db.query(`select * from admin_requests where id = $1`, [rid])).rows[0];

console.log('\n══════ قبل الإضافة ══════');
check('الدالة غير موجودة', !(await link(P.O, R.r1, P.W1, null, null)).ok);

await db.exec(fix);
console.log('\n══════ بعد الإضافة ══════');
let r = await link(P.S, R.r1, P.W1, null, null);
check('المشرف مرفوض', !r.ok && r.hint === 'not_allowed', r.hint ?? '');
r = await link(P.M, R.r1, P.W1, null, null);
check('العضو مرفوض', !r.ok && r.hint === 'not_allowed', r.hint ?? '');

r = await link(P.MON, R.r1, P.W1, null, null);
let a1 = await prof(P.A1), w1 = await node(P.W1), r1 = await req(R.r1);
check('المراقب يربط طلب أنثى بعقدة موجودة', r.ok && w1.linked_user_id === P.A1, r.err ?? '');
check('الحساب: عضو مفعّل، مخفي من شجرة الرجال، رقمه مخفي، الاسم من عقدتها',
  a1.role === 'member' && a1.status === 'active' && a1.is_hidden_from_tree && a1.is_phone_hidden && a1.full_name === 'سارة خالد المحمدعلي',
  `${a1.role}/${a1.status}/${a1.full_name}`);
check('الطلب أُغلق «مقبول»', r1.status === 'approved' && r1.replied_by === P.MON);
const n1 = (await db.query(`select count(*)::int n from notifications where target_member_id = $1 and kind = 'join_approved'`, [P.A1])).rows[0].n;
check('وصلها إشعار «مرحباً بك»', n1 === 1);

r = await link(P.O, R.r1, P.W1, null, null);
check('طلب عولج من قبل مرفوض', !r.ok && r.hint === 'already_handled', r.hint ?? '');
r = await link(P.O, R.r2, P.W2, null, null);
check('عقدة مربوطة بحساب آخر مرفوضة', !r.ok && r.hint === 'node_taken', r.hint ?? '');
r = await link(P.O, R.r2, P.F, null, null);
check('عقدة ذكر مرفوضة', !r.ok && r.hint === 'not_female_node', r.hint ?? '');

r = await link(P.O, R.r2, null, P.F, 'هند');
const w2new = r.ok ? await node(r.rows[0].id) : null;
check('عقدة جديدة تحت أبيها باسمها + سلسلة الأب، مربوطة بحسابها',
  r.ok && w2new.parent_id === P.F && w2new.linked_user_id === P.A2 && w2new.full_name === 'هند خالد المحمدعلي', r.err ?? w2new?.full_name);
r = await link(P.O, R.r3, null, P.F, '  ');
check('بلا اسم مرفوض', !r.ok && r.hint === 'name_required', r.hint ?? '');
r = await link(P.O, R.r3, null, P.W1, 'مها');
check('أب ليس رجلاً مرفوض', !r.ok && r.hint === 'no_father', r.hint ?? '');
r = await link(P.O, R.rm, P.W1, null, null);
check('طلب ذكر مرفوض', !r.ok && r.hint === 'not_female', r.hint ?? '');
r = await link(P.O, R.rf, null, P.F, 'ريم');
check('ملف أنثى له أب في شجرة الرجال مرفوض (يصحَّح أولاً)', !r.ok && r.hint === 'has_father', r.hint ?? '');
r = await link(P.O, id(999), P.W1, null, null);
check('طلب غير موجود', !r.ok && r.hint === 'request_not_found', r.hint ?? '');
r = await link(P.O, R.r3, null, P.F, 'مها');
check('طلب «ربط» لأنثى يُقبل أيضاً', r.ok, r.err ?? '');

await db.exec(undo);
console.log('\n══════ بعد التراجع ══════');
check('الدالة حُذفت', !(await link(P.O, R.r2, P.W1, null, null)).ok);
check('الحسابات المربوطة تبقى', (await node(P.W1)).linked_user_id === P.A1);

console.log(`\n${pass} نجح · ${fail} فشل`);
process.exit(fail ? 1 : 0);
