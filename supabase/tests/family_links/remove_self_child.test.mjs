// تجربة 20261016150000 (remove_self_child — طلب المالك ٢٠٢٦-١٠-١٦ «حط زر حذف للكل») على قاعدة محلية معزولة
// (لا تلمس السيرفر): فوق الحي — حماية روابط العائلة (20261001150000) + إصلاح حارس الحذف (20261015170000)
// + مزامنة شجرة النساء وحارس مرسل الإشعار. قبل الترحيل (الدالة غير موجودة) ← بعده ← بعد التراجع.
// التشغيل: cd supabase/tests/family_links && node remove_self_child.test.mjs
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
const links = readFileSync(`${REPO}/migrations/20261001150000_protect_family_links.sql`, 'utf8');
const delFix = readFileSync(`${REPO}/migrations/20261015170000_profiles_delete_guard_fix.sql`, 'utf8');
const MIG = '20261016150000_remove_self_child';
const mig = readFileSync(`${REPO}/migrations/${MIG}.sql`, 'utf8');
const rb = readFileSync(`${REPO}/rollback/${MIG}_rollback.sql`, 'utf8');

// نسخ الحي لما تلمسه الدالة: أعمدة الطلب والإشعار، وحارس مرسل الإشعار (العضو = created_by نفسه)
const live = `
alter table public.admin_requests add column new_value text, add column created_at timestamptz default now();
create or replace function public.guard_notification_sender() returns trigger language plpgsql security definer
  set search_path to 'public' as $function$
declare me uuid := public.current_profile_id();
begin
  if auth.role() = 'service_role' or (auth.role() is null and session_user in ('postgres','supabase_admin','supabase_auth_admin')) then return new; end if;
  if me is null then return new; end if;
  if coalesce(public.current_user_role(), 'pending') in ('owner','admin','monitor','supervisor') then return new; end if;
  if coalesce(new.kind, '') in ('admin_broadcast','app_update') then raise exception 'notification_kind_not_allowed' using errcode = '42501'; end if;
  new.created_by := case when exists (select 1 from public.profiles p where p.id = me) then me end;
  return new;
end; $function$;
create trigger trg_a_guard_notification_sender before insert on public.notifications for each row execute function public.guard_notification_sender();
grant usage on schema auth to authenticated, anon;
`;

const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const P = { G: id(1), O: id(2), A: id(3), A2: id(4), MON: id(5), S: id(6), M1: id(7), M2: id(8), FR: id(9), PEND: id(10),
  FA: id(11), MV_AUTH: id(12) };
const K = { S1: id(101), S2: id(102), S3: id(103), S4: id(104), SD: id(105), SDA: id(106), SDO: id(107), S5: id(108),
  GS: id(109), S6: id(110), D6: id(111), SM: id(112), SF: id(113), SMV: id(114), S7: id(115), SP: id(116) };

let pass = 0, fail = 0;
const check = (l, ok, x = '') => { ok ? pass++ : fail++; console.log(`${ok ? '✅' : '❌'} ${l}${x ? ' — ' + x : ''}`); };

const db = new PGlite();
await db.exec(baseBody); await db.exec(preFns); await db.exec(baseTriggers); await db.exec(links); await db.exec(delFix);
await db.exec(live);
await db.exec(`
  insert into profiles(id, first_name, full_name, gender, role, status) values ('${P.G}', 'صلاح', 'صلاح الجد', 'male', 'member', 'active');
  insert into women_members(id, first_name, full_name, gender) values ('${P.G}', 'صلاح', 'صلاح الجد', 'male');
  insert into profiles(id, first_name, full_name, gender, role, status, father_id) values
    ('${P.O}', 'مالك', 'مالك صلاح', 'male', 'owner', 'active', '${P.G}'),
    ('${P.A}', 'بدر', 'بدر صلاح', 'male', 'admin', 'active', '${P.G}'),
    ('${P.A2}', 'خالد', 'خالد صلاح', 'male', 'admin', 'active', '${P.G}'),
    ('${P.FA}', 'مجمّد', 'مدير مجمّد', 'male', 'admin', 'frozen', '${P.G}'),
    ('${P.MON}', 'علي', 'علي صلاح', 'male', 'monitor', 'active', '${P.G}'),
    ('${P.S}', 'سعد', 'سعد صلاح', 'male', 'supervisor', 'active', '${P.G}'),
    ('${P.M1}', 'حسن', 'حسن صلاح', 'male', 'member', 'active', '${P.G}'),
    ('${P.M2}', 'عمر', 'عمر صلاح', 'male', 'member', 'active', '${P.G}'),
    ('${P.FR}', 'فهد', 'فهد صلاح', 'male', 'member', 'frozen', '${P.G}'),
    ('${P.PEND}', 'جديد', 'جديد صلاح', 'male', 'pending', 'pending', '${P.G}');
  insert into auth.users(id) values ('${P.O}'), ('${P.A}'), ('${P.A2}'), ('${P.FA}'), ('${P.MON}'), ('${P.S}'),
    ('${P.M1}'), ('${P.M2}'), ('${P.FR}'), ('${P.PEND}');
  -- حساب منقول: معرّف دخول مختلف وملفه M2
  insert into auth.users(id, raw_app_meta_data) values ('${P.MV_AUTH}', '{"profile_id": "${P.M2}"}');
  insert into profiles(id, first_name, full_name, gender, role, status, father_id, is_deceased) values
    ('${K.S1}', 'سعود', 'سعود حسن صلاح', 'male', 'member', 'pending', '${P.M1}', false),
    ('${K.S2}', 'ناصر', 'ناصر حسن صلاح', 'male', 'member', 'active', '${P.M1}', false),
    ('${K.S3}', 'يوسف', 'يوسف حسن صلاح', 'male', 'member', 'active', '${P.M1}', false),
    ('${K.S4}', 'محمد', 'محمد حسن صلاح', 'male', 'member', 'active', '${P.M1}', false),
    ('${K.SD}', 'جاسم', 'جاسم حسن صلاح', 'male', 'member', 'active', '${P.M1}', true),
    ('${K.SDA}', 'راشد', 'راشد بدر صلاح', 'male', 'member', 'active', '${P.A}', true),
    ('${K.SDO}', 'مبارك', 'مبارك مالك صلاح', 'male', 'member', 'active', '${P.O}', true),
    ('${K.S5}', 'طلال', 'طلال حسن صلاح', 'male', 'member', 'active', '${P.M1}', false),
    ('${K.S6}', 'ماجد', 'ماجد حسن صلاح', 'male', 'member', 'active', '${P.M1}', false),
    ('${K.SM}', 'زيد', 'زيد علي صلاح', 'male', 'member', 'active', '${P.MON}', false),
    ('${K.SF}', 'نايف', 'نايف فهد صلاح', 'male', 'member', 'active', '${P.FR}', false),
    ('${K.SMV}', 'سالم', 'سالم عمر صلاح', 'male', 'member', 'active', '${P.M2}', false),
    ('${K.S7}', 'وليد', 'وليد حسن صلاح', 'male', 'member', 'pending', '${P.M1}', false),
    ('${K.SP}', 'فيصل', 'فيصل جديد صلاح', 'male', 'member', 'active', '${P.PEND}', false);
  insert into profiles(id, first_name, full_name, gender, role, status, father_id) values
    ('${K.GS}', 'حفيد', 'حفيد طلال حسن', 'male', 'member', 'active', '${K.S5}');
  insert into women_members(id, first_name, full_name, gender, parent_id) values ('${K.D6}', 'نورة', 'نورة ماجد حسن', 'female', '${K.S6}');
  insert into auth.users(id) values ('${K.S3}');
  insert into auth.users(id, raw_app_meta_data) values ('${id(199)}', '{"profile_id": "${K.S4}"}');
  -- طلب «إضافة ابن» المعلّق: الطلب عن الأب والابن في new_value (الآيفون يرسل حروفاً كبيرة)
  insert into admin_requests(member_id, requester_id, request_type, status, new_value) values
    ('${P.M1}', '${P.M1}', 'child_add', 'pending', upper('${K.S1}')),
    ('${P.M1}', '${P.M1}', 'child_add', 'approved', '${K.S1}'),
    ('${P.M1}', '${P.M1}', 'child_add', 'pending', '${K.S7}'),
    ('${P.M1}', '${P.M1}', 'child_add', 'pending', '${K.S5}'),
    ('${K.S1}', '${P.M1}', 'tree_edit', 'pending', null);
  delete from notifications;`);

const q = async (sql, params = []) => (await db.query(sql, params)).rows;
const one = async (sql, params = []) => (await q(sql, params))[0];
const exists = async pid => (await one(`select count(*)::int n from profiles where id = $1`, [pid])).n === 1;
const womenExists = async wid => (await one(`select count(*)::int n from women_members where id = $1`, [wid])).n === 1;

// المتصل: uuid · {sub, pid} (حساب منقول) · 'anon' · 'noclaims' · 'maint' (صيانة SQL)
async function as(who, sql, params = []) {
  const claims = who === 'maint' || who === 'anon' ? (who === 'anon' ? JSON.stringify({ role: 'anon' }) : '')
    : who === 'noclaims' ? JSON.stringify({ role: 'authenticated' })
    : JSON.stringify(typeof who === 'string' ? { sub: who, role: 'authenticated' } : { sub: who.sub, role: 'authenticated', app_metadata: { profile_id: who.pid } });
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [claims]);
  if (who !== 'maint') await db.exec(`set role ${who === 'anon' ? 'anon' : 'authenticated'}`);
  try { return { ok: true, rows: (await db.query(sql, params)).rows }; }
  catch (e) { return { ok: false, err: e.message, hint: e.hint, code: e.code }; }
  finally { if (who !== 'maint') await db.exec('reset role'); await db.query(`select set_config('request.jwt.claims', '', false)`); }
}
const removeAs = async (who, child) => {
  await db.exec('delete from notifications');
  return as(who, `select public.remove_self_child($1::uuid) as r`, [child]);
};
const childNotes = async () => q(`select target_member_id t, title, body, created_by from notifications
  where kind = 'admin_edit_child_remove' order by target_member_id`);

console.log('══════ ٠) قبل الترحيل: الدالة غير موجودة (التطبيق يعرض «تحتاج تحديث السيرفر») ══════');
let r = await removeAs(P.M1, K.S1);
check('استدعاؤها يفشل بـ 42883 (غير موجودة)', !r.ok && r.code === '42883', r.err);

console.log('\n══════ ١) الترحيل ══════');
await db.exec(mig);
await db.exec(mig);
check('الترحيل يُعاد تطبيقه بلا خطأ', true);
const acl = await one(`select coalesce(proacl::text, '') a, prosecdef s, proconfig::text cfg from pg_proc where proname = 'remove_self_child'`);
check('SECURITY DEFINER و search_path = public', acl.s === true && /search_path=public/.test(acl.cfg), acl.cfg);
check('لا تنفيذ لـ public ولا anon', !/(^|[{,])=X/.test(acl.a) && !/anon=/.test(acl.a), acl.a);
check('التنفيذ لـ authenticated', /authenticated=X/.test(acl.a), acl.a);

console.log('\n══════ ٢) الأب يحذف ابنه (عضو) ══════');
check('قبل: الابن ونسخته في شجرة النساء موجودان', await exists(K.S1) && await womenExists(K.S1));
r = await removeAs(P.M1, K.S1);
check('ترجع {deleted: true, id}', r.ok && r.rows[0].r.deleted === true && r.rows[0].r.id === K.S1, JSON.stringify(r.ok ? r.rows[0].r : r.err));
check('السجل حُذف من profiles', !(await exists(K.S1)));
check('ونسخته في شجرة النساء حُذفت (المزامنة الحالية)', !(await womenExists(K.S1)));
const reqs = await q(`select request_type, status, new_value from admin_requests order by request_type, status, new_value`);
check('طلب «إضافة ابن» المعلّق عنه حُذف (حروف كبيرة)', !reqs.some(x => x.status === 'pending' && x.new_value?.toLowerCase() === K.S1));
check('وطلبه هو (member_id = الابن) حُذف بالـ CASCADE', !reqs.some(x => x.request_type === 'tree_edit'));
check('الطلب المقبول عنه يبقى للتاريخ، وطلبات الأبناء الآخرين كما هي',
  reqs.some(x => x.status === 'approved' && x.new_value === K.S1)
  && reqs.some(x => x.status === 'pending' && x.new_value === K.S7) && reqs.some(x => x.status === 'pending' && x.new_value === K.S5));
let notes = await childNotes();
check('أُشعر المالك والمديران المفعّلان فقط (لا المجمّد ولا المراقب ولا المشرف ولا الأب)',
  JSON.stringify(notes.map(n => n.t).sort()) === JSON.stringify([P.O, P.A, P.A2].sort()), notes.map(n => n.t).join(','));
check('العنوان والنص', notes.every(n => n.title === 'حذف ابن من الشجرة' && n.body === 'حسن حذف ابنه «سعود» من الشجرة'), notes[0]?.body);
check('المرسل = الأب', notes.every(n => n.created_by === P.M1));

console.log('\n══════ ٣) ابن غيره / غير موجود ══════');
r = await removeAs(P.M2, K.S2);
check('عضو آخر لا يحذف ابن غيره (not_your_child)', !r.ok && r.hint === 'not_your_child' && r.code === '42501', r.err);
check('الابن باقٍ', await exists(K.S2));
r = await removeAs(P.A, K.S2);
check('ولا المدير عبر هذه الدالة (ليس أباه)', !r.ok && r.hint === 'not_your_child', r.err);
r = await removeAs(P.M1, id(999));
check('معرّف غير موجود (not_your_child)', !r.ok && r.hint === 'not_your_child', r.err);
r = await removeAs(P.M1, P.M1);
check('لا يحذف نفسه بها (not_your_child)', !r.ok && r.hint === 'not_your_child', r.err);
check('ولا إشعار لأحد', (await childNotes()).length === 0);

console.log('\n══════ ٤) ابن له حساب دخول ══════');
r = await removeAs(P.M1, K.S3);
check('حساب بمعرّفه → has_account برسالة عربية', !r.ok && r.hint === 'has_account' && r.err === 'لهذا الابن حساب دخول — يحذفه المالك أو المدير', r.err);
r = await removeAs(P.M1, K.S4);
check('حساب منقول إليه (app_metadata.profile_id) → has_account', !r.ok && r.hint === 'has_account', r.err);
check('الاثنان باقيان', await exists(K.S3) && await exists(K.S4));

console.log('\n══════ ٥) المتوفى ══════');
r = await removeAs(P.M1, K.SD);
check('العضو لا يحذف ابنه المتوفى (deceased_protected)', !r.ok && r.hint === 'deceased_protected' && r.err === 'سجل متوفى — يحذفه المالك أو المدير', r.err);
check('السجل باقٍ', await exists(K.SD));
r = await removeAs(P.A, K.SDA);
check('المدير يحذف ابنه المتوفى', r.ok && r.rows[0].r.deleted === true && !(await exists(K.SDA)), r.err);
notes = await childNotes();
check('إشعار المالك والمدير الآخر — لا المتصل', JSON.stringify(notes.map(n => n.t).sort()) === JSON.stringify([P.O, P.A2].sort()), notes.map(n => n.t).join(','));
r = await removeAs(P.O, K.SDO);
check('المالك يحذف ابنه المتوفى', r.ok && !(await exists(K.SDO)), r.err);
notes = await childNotes();
check('إشعار المديرَين — لا المالك', JSON.stringify(notes.map(n => n.t).sort()) === JSON.stringify([P.A, P.A2].sort()), notes.map(n => n.t).join(','));
check('النص باسم المالك الأول', notes.every(n => n.body === 'مالك حذف ابنه «مبارك» من الشجرة' && n.created_by === P.O), notes[0]?.body);

console.log('\n══════ ٦) ابن له أبناء/بنات (حماية روابط العائلة) ══════');
r = await removeAs(P.M1, K.S5);
check('له ابن → family_links_protected برسالة الحارس العربية', !r.ok && r.hint === 'family_links_protected' && r.code === '23503'
  && r.err.startsWith('لا يمكن حذف «طلال حسن صلاح»'), r.err);
check('السجل وحفيده باقيان', await exists(K.S5) && await exists(K.GS));
check('وطلب إضافته المعلّق باقٍ (المعاملة تراجعت)', (await one(`select count(*)::int n from admin_requests where new_value = $1 and status = 'pending'`, [K.S5])).n === 1);
check('ولا إشعار', (await childNotes()).length === 0);
r = await removeAs(P.M1, K.S6);
check('له ابنة في شجرة النساء → family_links_protected', !r.ok && r.hint === 'family_links_protected', r.err);
check('السجل وابنته باقيان', await exists(K.S6) && await womenExists(K.D6) && await womenExists(K.S6));

console.log('\n══════ ٧) الأدوار والحالات ══════');
r = await removeAs(P.MON, K.SM);
check('المراقب كأب يحذف ابنه', r.ok && !(await exists(K.SM)), r.err);
r = await removeAs({ sub: P.MV_AUTH, pid: P.M2 }, K.SMV);
check('الحساب المنقول (current_profile_id) يحذف ابنه', r.ok && !(await exists(K.SMV)), r.err);
notes = await childNotes();
check('والمرسل = ملفه (لا معرّف الدخول)', notes.length === 3 && notes.every(n => n.created_by === P.M2), notes.map(n => n.created_by).join(','));
r = await removeAs(P.FR, K.SF);
check('المجمّد لا يحذف (not_allowed)', !r.ok && r.hint === 'not_allowed' && r.code === '42501', r.err);
r = await removeAs(P.PEND, K.SP);
check('المعلّق لا يحذف (not_allowed)', !r.ok && r.hint === 'not_allowed', r.err);
r = await removeAs('noclaims', K.S7);
check('بلا هوية (غير مسجّل الدخول) لا يحذف (not_allowed)', !r.ok && r.hint === 'not_allowed', r.err);
r = await removeAs('anon', K.S7);
check('الزائر anon لا يملك التنفيذ أصلاً', !r.ok && r.code === '42501' && /permission denied/.test(r.err), r.err);
check('الأبناء باقون', await exists(K.SF) && await exists(K.SP) && await exists(K.S7));

console.log('\n══════ ٨) التراجع ══════');
await db.exec(rb);
check('الدالة حُذفت', (await one(`select count(*)::int n from pg_proc where proname = 'remove_self_child'`)).n === 0);
r = await removeAs(P.M1, K.S7);
check('استدعاؤها بعد التراجع = غير موجودة (42883)', !r.ok && r.code === '42883', r.err);
await db.exec(rb);
check('التراجع يُعاد بلا خطأ', true);
await db.exec(mig);
r = await removeAs(P.M1, K.S7);
check('إعادة الترحيل بعد التراجع تعمل', r.ok && !(await exists(K.S7)), r.err);

console.log(`\nالنتيجة: ${pass} نجح، ${fail} فشل`);
process.exit(fail ? 1 : 0);
