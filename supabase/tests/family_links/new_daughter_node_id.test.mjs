// تجربة 20261127170000_new_daughter_node_id على قاعدة محلية معزولة (لا تلمس السيرفر):
//   «بنت جديدة» من مربّع «الربط»: عقدة شجرة النساء الجديدة بمعرّف ملف صاحبة الحساب و linked_user_id = ملفها،
//   والصلاحيات والحرّاس كما في 20261024181856 حرفياً، ثم التراجع يعيد النص الحي كما كان.
// التشغيل: cd supabase/tests/family_links && node new_daughter_node_id.test.mjs
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
// المزامنة الحية (20261127150000): لا تحذف عقدة صاحب الحساب المربوطة بمعرّف ملفه
const liveSync = grab(readFileSync(`${REPO}/migrations/20261127150000_daughter_daughters.sql`, 'utf8'), 'sync_profile_update_to_women');
const mig = readFileSync(`${REPO}/migrations/20261127170000_new_daughter_node_id.sql`, 'utf8');
const undo = readFileSync(`${REPO}/rollback/20261127170000_new_daughter_node_id_rollback.sql`, 'utf8');

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

const def = async () => (await db.query(`select pg_get_functiondef('public.link_woman_account(uuid,uuid,uuid,text)'::regprocedure) d`)).rows[0].d;
const acl = async () => (await db.query(`select proacl::text a, prosecdef s from pg_proc where oid = 'public.link_woman_account(uuid,uuid,uuid,text)'::regprocedure`)).rows[0];

await db.exec(liveSync);
await db.exec(fix);
const before = await def();
const aclBefore = await acl();
await db.exec(mig);
console.log('\n══════ بعد الترحيل ══════');
check('النص تغيّر في فرع العقدة الجديدة فقط', (await def()) !== before && (await def()).includes('values (p.id, nm,'));
const aclAfter = await acl();
check('الصلاحيات (منح التنفيذ و SECURITY DEFINER) كما هي', aclAfter.a === aclBefore.a && aclAfter.s === aclBefore.s, aclAfter.a);

let r = await link(P.S, R.r2, null, P.F, 'هند');
check('المشرف مرفوض', !r.ok && r.hint === 'not_allowed', r.hint ?? '');
r = await link(P.M, R.r2, null, P.F, 'هند');
check('العضو مرفوض', !r.ok && r.hint === 'not_allowed', r.hint ?? '');

r = await link(P.MON, R.r2, null, P.F, 'هند');
const w2 = r.ok ? await node(r.rows[0].id) : null;
check('المراقب: «بنت جديدة» عقدتها بمعرّف ملفها', r.ok && r.rows[0].id === P.A2 && w2?.id === P.A2, r.err ?? r.rows?.[0]?.id);
check('linked_user_id = ملفها وأبوها خالد واسمها بسلسلة الأب',
  w2?.linked_user_id === P.A2 && w2?.parent_id === P.F && w2?.full_name === 'هند خالد المحمدعلي' && w2?.gender === 'female',
  `${w2?.linked_user_id}/${w2?.full_name}`);
const a2 = await prof(P.A2);
check('الحساب: عضو مفعّل مخفي من شجرة الرجال', a2.role === 'member' && a2.status === 'active' && a2.is_hidden_from_tree);
check('الطلب أُغلق «مقبول» بيد المراقب', (await req(R.r2)).status === 'approved' && (await req(R.r2)).replied_by === P.MON);
const n2 = (await db.query(`select count(*)::int n from notifications where target_member_id = $1 and kind = 'join_approved'`, [P.A2])).rows[0].n;
check('إشعار «مرحباً بك» واحد', n2 === 1);

// عقدة بمعرّفها موجودة من قبل ← تُربط بها لا بعقدة ثانية
await db.exec(`insert into women_members(id, first_name, full_name, parent_id, gender) values ('${P.A3}', 'مها', 'مها خالد المحمدعلي', '${P.F}', 'female')`);
r = await link(P.O, R.r3, null, P.F, 'مها');
check('عقدة بمعرّفها موجودة ← node_exists بلا عقدة ثانية', !r.ok && r.hint === 'node_exists', r.hint ?? '');
check('الطلب باقٍ معلّقاً', (await req(R.r3)).status === 'pending');
r = await link(P.O, R.r3, P.A3, null, null);
check('«ربط» بعقدتها الموجودة كما كان', r.ok && (await node(P.A3)).linked_user_id === P.A3, r.err ?? '');

r = await link(P.O, R.r1, P.W1, null, null);
check('ربط بعقدة موجودة بمعرّف آخر كما كان', r.ok && (await node(P.W1)).linked_user_id === P.A1, r.err ?? '');
r = await link(P.O, R.rm, null, P.F, 'علي');
check('طلب ذكر مرفوض كما كان', !r.ok && r.hint === 'not_female', r.hint ?? '');
r = await link(P.O, R.rf, null, P.F, 'ريم');
check('أنثى لها أب في شجرة الرجال مرفوضة كما كان', !r.ok && r.hint === 'has_father', r.hint ?? '');

await db.exec(undo);
console.log('\n══════ بعد التراجع ══════');
check('النص الحي عاد حرفياً', (await def()) === before);
check('العقدة المنشأة تبقى مربوطة', (await node(P.A2)).linked_user_id === P.A2);

console.log(`\n${pass} نجح · ${fail} فشل`);
process.exit(fail ? 1 : 0);
