// تجربة 20261111150000_admin_request_sent_info («من أرسل الطلب ومن أين» — طلب المالك ٢٠٢٦-١١-١١) على قاعدة محلية
// معزولة (لا تلمس السيرفر). فوق نسخة الحي من مشغّلات admin_requests: حارس الإدراج (نصّ الحي بعد ترقيعاته)،
// مسار الموافقات ٢، قفل المحتوى. يفحص: المسار الصحيح والفاسد والمتجاوز للحد (لا رفض أبداً)، الجهاز من الترويسات
// (موجودة/غائبة/فاسدة/مفتاح الخدمة) واستبدال ما يرسله العميل، طلبات دوال السيرفر، الثبات بعد الإدراج (للإدارة
// ومفتاح الخدمة والصيانة)، «من ردّ ومتى» عند الإغلاق، ترتيب المشغّلات، التراجع، ثم تُعاد التجارب القائمة كاملة
// والترحيل مثبّت (حارس الإدراج، decide_admin_request، مسار الموافقات ١ و٢).
// التشغيل: cd supabase/tests/family_links && node admin_request_sent_info.test.mjs
import { PGlite } from '@electric-sql/pglite';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
process.on('unhandledRejection', e => { console.log('خطأ:', e.message, e.where ?? '', (e.query ?? '').slice(0, 300)); process.exit(2); });
const HERE = fileURLToPath(new URL('./', import.meta.url));
const REPO = fileURLToPath(new URL('../../', import.meta.url));
const read = p => readFileSync(`${REPO}/${p}`, 'utf8');
const base = readFileSync(new URL('./base.sql', import.meta.url), 'utf8');
const [baseBody, rest] = base.split('-- ─── المشغّلات');
const baseTriggers = rest.slice(rest.indexOf('\n') + 1);
const grab = (src, name) => { const i = src.indexOf(`create or replace function public.${name}(`); return src.slice(i, src.indexOf('$function$;', i) + '$function$;'.length); };
const preFns = ['adopt_tree_profile', 'merge_member_into_tree', 'women_auto_merge_wife']
  .map(n => grab(read('rollback/20261001150000_protect_family_links_rollback.sql'), n)).join('\n\n');
const between = (src, a, b) => { const i = src.indexOf(a); if (i < 0) throw new Error('غاب: ' + a.slice(0, 60)); const j = src.indexOf(b, i + a.length); return src.slice(i, j + b.length); };

// نسخة الحي من تجربة مسار الموافقات ٢ (مصدر واحد): الجداول والسياسات والإشعارات وpg_cron
const v2src = readFileSync(HERE + 'approvals_v2.test.mjs', 'utf8');
const tpl = (src, name) => { const s = between(src, `const ${name} = \``, '`;'); return Function(`"use strict"; return ${s.slice(s.indexOf('`'), -1)};`)(); };
const live = tpl(v2src, 'live');
const CRON = tpl(v2src, 'CRON');

const links = read('migrations/20261001150000_protect_family_links.sql');
const guard0 = read('migrations/20261004200000_admin_requests_insert_guard.sql');
const decideMig = read('migrations/20261007170000_decide_admin_request.sql');
const wfMig = read('migrations/20261015120000_approvals_workflow.sql');
const ownerFix = read('migrations/20261015130000_approvals_owner_own_request.sql');
const infoMig = read('migrations/20261015150000_approvals_info_fields.sql');
const delFix = read('migrations/20261015170000_profiles_delete_guard_fix.sql');
const v2 = read('migrations/20261016120000_approvals_v2.sql');
// قفل المحتوى (٢٠٢٦-١٠-٢٤) — قسمه وحده من الدفعة
const payloadLock = between(read('migrations/20261024130000_audit_server_batch.sql'),
  '-- ─── ٦) قفل محتوى الطلب', 'for each row execute function public.trg_admin_request_payload_lock();');
// حارس الإدراج الحي: نسخة الشروط (٢٠٢٦-١٠-٢٨) ثم ترقيعتا relative_add (١٠-٢٩) وlineage_request (١١-٠٧) كما هما
const guardTerms = between(read('migrations/20261028180000_terms_compliance.sql'),
  'CREATE OR REPLACE FUNCTION public.guard_admin_request_insert()', '$function$;');
const guardPatch = f => between(read(f), "do $mig$\ndeclare d text := pg_get_functiondef('public.guard_admin_request_insert()'", 'end $mig$;');
const guardPatches = [guardPatch('migrations/20261029140000_self_relatives_via_approval.sql'),
                      guardPatch('migrations/20261107120000_daughter_sons_lineage.sql')].join('\n');

const MIG = '20261111150000_admin_request_sent_info';
const mig = read(`migrations/${MIG}.sql`);
const rollback = read(`rollback/${MIG}_rollback.sql`);

// md5 نصّ الدوال في السيرفر الحي ٢٠٢٦-١١-١١ (قراءة فقط) بلا التعليقات والأسطر الفارغة (بعضها طُبّق بلا تعليقات)
// — مشغّلات admin_requests المحلية = منطق الحي حرفياً
const LIVE_MD5 = {
  guard_admin_request_insert: 'fe1e25739f3e8166fb8b505380e4efa4',
  set_admin_request_stage: '118d0016c4e321ad7ae36f910213867a',
  guard_admin_request_workflow: 'a151dfa3e65788f02f6fccdbd556038d',
  log_admin_request_submitted: '83080400394815a2834e94450c6ae918',
  trg_admin_request_payload_lock: '6adbc5301fed85d8895d435b744d6df7',
};
const NORM_MD5 = `md5(btrim(regexp_replace(regexp_replace(p.prosrc, '[ \\t]*--[^\\n]*', '', 'g'), '\\n(\\s*\\n)+', E'\\n', 'g'), E'\\n '))`;

const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const U = s => s.toUpperCase();
const P = { O: id(1), A: id(2), MON: id(4), M: id(10), M2: id(11), PEND: id(14), G: id(17) };

let pass = 0, fail = 0;
const check = (l, ok, x = '') => { ok ? pass++ : fail++; console.log(`${ok ? '✅' : '❌'} ${l}${x ? ' — ' + x : ''}`); };

const db = new PGlite();
await db.exec(baseBody); await db.exec(preFns); await db.exec(baseTriggers); await db.exec(links);
await db.exec(live); await db.exec(guard0); await db.exec(decideMig);
await db.exec(`
  insert into profiles(id, first_name, full_name, gender, role, status) values ('${P.G}', 'صلاح', 'صلاح الجد', 'male', 'member', 'active');
  insert into women_members(id, first_name, full_name, gender) values ('${P.G}', 'صلاح', 'صلاح الجد', 'male');
  insert into profiles(id, first_name, full_name, gender, role, status) values
    ('${P.O}', 'مالك', 'المالك', 'male', 'owner', 'active'),
    ('${P.A}', 'بدر', 'بدر المدير', 'male', 'admin', 'active'),
    ('${P.MON}', 'علي', 'علي المراقب', 'male', 'monitor', 'active'),
    ('${P.M}', 'حسن', 'حسن صلاح المحمدعلي', 'male', 'member', 'active'),
    ('${P.M2}', 'عمر', 'عمر صلاح', 'male', 'member', 'active'),
    ('${P.PEND}', 'جديد', 'مسجّل معلّق', 'male', 'pending', 'pending');
  update profiles set father_id = '${P.G}' where id in ('${P.M}', '${P.M2}');
  insert into auth.users(id) values ('${P.O}'), ('${P.A}'), ('${P.MON}'), ('${P.M}'), ('${P.M2}'), ('${P.PEND}');
  grant select, insert, update on public.profiles to authenticated;`);
await db.exec(CRON);
await db.exec(wfMig); await db.exec(ownerFix); await db.exec(infoMig); await db.exec(delFix); await db.exec(v2);
await db.exec(payloadLock); await db.exec(guardTerms); await db.exec(guardPatches);
// دالة سيرفر تُنشئ طلباً كما تفعل private.self_relative_request (relative_add من الدوال فقط)
await db.exec(`
  create or replace function public.test_rpc_relative_add() returns uuid language plpgsql security definer
    set search_path to 'public' as $f$
  declare me uuid := public.current_profile_id(); rid uuid;
  begin
    perform set_config('app.self_relative_rpc', 'on', true);
    insert into public.admin_requests (member_id, requester_id, request_type, status, details, new_value)
    values (me, me, 'relative_add', 'pending', '{"v":1,"rpc":"add_self_wife","args":{"p_name":"س"}}', 'wife') returning id into rid;
    perform set_config('app.self_relative_rpc', '', true);
    return rid;
  end $f$;
  grant execute on function public.test_rpc_relative_add() to authenticated;`);

const q = async (sql, params = []) => (await db.query(sql, params)).rows;
const one = async (sql, params = []) => (await q(sql, params))[0];

// المتصل: uuid (authenticated) · 'service' (مفتاح الخدمة) · 'maint' (صيانة SQL بلا JWT)؛ والترويسات كما يكتبها PostgREST
async function as(who, sql, params = [], headers = null) {
  const claims = who === 'maint' ? '' : JSON.stringify(who === 'service' ? { role: 'service_role' } : { sub: who, role: 'authenticated' });
  const role = who === 'maint' || who === 'service' ? null : 'authenticated';
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [claims]);
  await db.query(`select set_config('request.headers', $1, false)`, [headers === null ? '' : typeof headers === 'string' ? headers : JSON.stringify(headers)]);
  if (role) await db.exec(`set role ${role}`);
  try { return { ok: true, rows: (await db.query(sql, params)).rows }; }
  catch (e) { return { ok: false, err: e.message, hint: e.hint }; }
  finally {
    if (role) await db.exec('reset role');
    await db.query(`select set_config('request.jwt.claims', '', false), set_config('request.headers', '', false)`);
  }
}
const IOS = { 'x-client-info': 'supabase-swift/2.43.1', 'x-app-platform': 'ios', 'x-app-version': '1.0.2', 'x-app-build': '51',
              'user-agent': 'FamilyTreeV2/51 CFNetwork' };
// طلب «تغيير الاسم» عن نفسه — أبسط طلب يمرّ الحارس لكل عضو
async function send(who, sentFrom, headers = IOS, extra = {}) {
  // sentFrom === undefined: بلا العمود أصلاً (النسخ القديمة)
  const cols = ['member_id', 'requester_id', 'request_type', 'status', 'new_value', 'details',
                ...(sentFrom === undefined ? [] : ['sent_from']), ...Object.keys(extra)];
  const vals = [U(who), U(who), 'name_change', 'pending', 'اسم جديد', 'طلب تغيير الاسم',
                ...(sentFrom === undefined ? [] : [typeof sentFrom === 'string' ? sentFrom : JSON.stringify(sentFrom)]), ...Object.values(extra)];
  const ret = sentFrom === undefined && !('sent_via' in extra) && !(await hasCol()) ? 'id, status' : 'id, sent_from, sent_via, status';
  const ph = vals.map((_, i) => `$${i + 1}${cols[i] === 'sent_from' || cols[i] === 'sent_via' ? '::jsonb' : cols[i].endsWith('_id') ? '::uuid' : ''}`);
  const r = await as(who, `insert into public.admin_requests (${cols.join(', ')}) values (${ph.join(', ')})
                           returning ${ret}`, vals, headers);
  return r.ok ? { ok: true, ...r.rows[0] } : r;
}
const hasCol = async () => (await one(`select count(*)::int n from information_schema.columns
  where table_schema = 'public' and table_name = 'admin_requests' and column_name = 'sent_from'`)).n === 1;
const clean = async () => db.exec(`delete from admin_request_steps; delete from admin_requests; delete from notifications;
  do $c$ begin if to_regclass('public.admin_request_events') is not null then delete from public.admin_request_events; end if; end $c$;`);
// سياسة «سحب طلبي المعلّق» كما في الحي (20261024130000 القسم ٥)
await db.exec(`create policy admin_requests_delete_own_pending on public.admin_requests for delete to authenticated
  using (status = 'pending' and requester_id = any (array[auth.uid(), public.current_profile_id()]) and public.is_approved_member());
  drop policy if exists admin_requests_delete_by_scope on public.admin_requests;
  create policy admin_requests_delete_by_scope on public.admin_requests for delete to authenticated
  using (public.current_user_role() = any (array['owner', 'admin']) and public.can_handle_admin_request(request_type));
  grant delete on public.admin_requests to authenticated;`);
const events = async rid => (await q(`select action, actor_id, actor_role, note from admin_request_events
  where request_id = $1 order by at, id`, [rid]));
const acts = async rid => (await events(rid)).map(e => e.action).join(',');

console.log('══════ ٠) النسخة المحلية = الحي (md5) ══════');
const md5 = Object.fromEntries((await q(`select p.proname, ${NORM_MD5} m from pg_proc p where p.pronamespace = 'public'::regnamespace
  and p.proname = any($1)`, [Object.keys(LIVE_MD5)])).map(r => [r.proname, r.m]));
for (const [k, v] of Object.entries(LIVE_MD5)) check(`${k} = نصّ الحي`, md5[k] === v, md5[k]);

const shape = async () => JSON.stringify([
  await q(`select column_name, data_type, is_nullable, coalesce(column_default, '') d from information_schema.columns
             where table_schema = 'public' and table_name = 'admin_requests' order by 1`),
  await q(`select tgrelid::regclass::text t, tgname, pg_get_triggerdef(oid) d from pg_trigger
             where tgrelid in ('public.admin_requests'::regclass, 'public.profiles'::regclass) and not tgisinternal order by 1, 2`),
  await q(`select relname from pg_class where relnamespace = 'public'::regnamespace and relkind in ('r', 'v', 'S') order by 1`),
  await q(`select p.oid::regprocedure::text f, md5(p.prosrc) m from pg_proc p where p.pronamespace = 'public'::regnamespace order by 1`),
  await q(`select policyname, cmd, coalesce(qual, '') qq, coalesce(with_check, '') w from pg_policies
             where tablename = 'admin_requests' order by 1`),
  await q(`select grantee, privilege_type from information_schema.table_privileges where table_name = 'admin_requests' order by 1, 2`)]);
const before = await shape();
// قبل الترحيل: العمود غائب — الآيفون الجديد يرسله فيُرفض الإدراج (فيعيده بلا sent_from)
const pre = await send(P.M, [{ icon: 'person.fill', title: 'الملف الشخصي' }]);
check('قبل الترحيل: إدراج sent_from يفشل بعمود غائب (يعيده الآيفون بلا العمود)', !pre.ok && /sent_from/.test(pre.err), pre.err);
await clean();

await db.exec(mig);
const once = await shape();
await db.exec(mig);
check('الترحيل يُعاد تطبيقه بلا تغيير', (await shape()) === once);

console.log('\n══════ ١) ترتيب المشغّلات ══════');
const order = async ev => (await q(`select tgname from pg_trigger where tgrelid = 'public.admin_requests'::regclass and not tgisinternal
  and (tgtype & 2) = 2 and (tgtype & $1) <> 0 order by tgname collate "C"`, [ev])).map(r => r.tgname);
const insOrder = await order(4), updOrder = await order(16);
check('الإدراج: المشغّل الجديد آخر مشغّلات BEFORE', insOrder.at(-1) === 'trg_zzz_admin_request_sent_info'
  && insOrder.includes('trg_guard_admin_request_insert') && insOrder.includes('trg_zz_admin_request_stage'), insOrder.join(' → '));
check('التحديث: المشغّل الجديد آخر مشغّلات BEFORE', updOrder.at(-1) === 'trg_zzz_admin_request_sent_info'
  && updOrder.includes('trg_admin_request_payload_lock') && updOrder.includes('trg_zz_admin_request_workflow'), updOrder.join(' → '));

console.log('\n══════ ٢) المسار (sent_from) — صحيح أو NULL، والإدراج لا يُرفض أبداً ══════');
const path3 = [{ icon: 'tree.fill', title: 'شجرة النساء' }, { icon: 'person.fill', title: 'فاطمة فيصل عبدالله' }, { icon: 'plus', title: 'طلب إضافة أبناء' }];
let r = await send(P.M, path3);
check('مسار من ٣ خطوات يُحفظ كما هو', r.ok && JSON.stringify(r.sent_from) === JSON.stringify(path3), JSON.stringify(r.sent_from ?? r.err));
r = await send(P.M, [{ icon: ' tree.fill ', title: '  شجرة   النساء\n', extra: 'x', at: 1 }, { title: 'الأسرة', icon: '' }]);
check('يُطبَّع: الحقلان فقط، المسافات مطويّة، والرمز الفارغ مقبول', r.ok
  && JSON.stringify(r.sent_from) === JSON.stringify([{ icon: 'tree.fill', title: 'شجرة النساء' }, { icon: '', title: 'الأسرة' }]), JSON.stringify(r.sent_from));
const edge = [{ icon: 'a'.repeat(40), title: 'ب'.repeat(120) }];
r = await send(P.M, edge);
check('الحد الأقصى بالضبط (رمز ٤٠، عنوان ١٢٠، ٥ خطوات) مقبول', r.ok && JSON.stringify(r.sent_from) === JSON.stringify(edge)
  && (await send(P.M, Array(5).fill({ icon: 'plus', title: 'خطوة' }))).sent_from?.length === 5);
const bad = [
  ['ليس مصفوفة (كائن)', { icon: 'plus', title: 'x' }],
  ['نص JSON', '"شجرة"'],
  ['رقم', '7'],
  ['مصفوفة فارغة', []],
  ['٦ خطوات', Array(6).fill({ icon: 'plus', title: 'خطوة' })],
  ['عنصر ليس كائناً', ['شجرة', 'تفاصيل']],
  ['رمز رقم', [{ icon: 5, title: 'x' }]],
  ['عنوان غائب', [{ icon: 'plus' }]],
  ['رمز غائب', [{ title: 'x' }]],
  ['عنوان فارغ', [{ icon: 'plus', title: '   ' }]],
  ['عنوان ١٢١ حرفاً', [{ icon: 'plus', title: 'ب'.repeat(121) }]],
  ['رمز ٤١ حرفاً', [{ icon: 'a'.repeat(41), title: 'x' }]],
  ['رمز بحروف غريبة', [{ icon: '<script>', title: 'x' }]],
  ['خطوة صحيحة وأخرى فاسدة', [{ icon: 'plus', title: 'x' }, { icon: 'plus', title: null }]],
  ['JSON null', 'null'],
];
for (const [label, v] of bad) {
  r = await send(P.M, v);
  check(`فاسد → NULL والطلب يُحفظ: ${label}`, r.ok && r.sent_from === null && r.status === 'pending', r.ok ? JSON.stringify(r.sent_from) : r.err);
}
r = await send(P.M, undefined);
check('بلا مسار (النسخ القديمة) → NULL', r.ok && r.sent_from === null);
const huge = JSON.stringify([{ icon: 'plus', title: 'ب'.repeat(100000) }]);
r = await send(P.M, huge);
check('عنوان ضخم (١٠٠ ألف حرف) → NULL بلا رفض', r.ok && r.sent_from === null);

console.log('\n══════ ٣) الجهاز (sent_via) من الترويسات فقط ══════');
r = await send(P.M, path3);
const sv = r.sent_via;
check('آيفون: المنصة والنسخة والبناء والعميل والوقت', sv?.platform === 'ios' && sv.app_version === '1.0.2' && sv.app_build === '51'
  && sv.client === 'supabase-swift/2.43.1' && typeof sv.at === 'string' && Object.keys(sv).length === 5, JSON.stringify(sv));
check('لا يُحفظ غير هذه الحقول (لا user-agent ولا ترويسات أخرى)', !JSON.stringify(sv).includes('CFNetwork'));
r = await send(P.M, path3, IOS, { sent_via: JSON.stringify({ platform: 'hacked', app_version: '9.9', at: '2000-01-01' }) });
check('ما يرسله العميل في sent_via يُستبدل دائماً', r.ok && r.sent_via.platform === 'ios' && r.sent_via.app_version === '1.0.2'
  && r.sent_via.at !== '2000-01-01', JSON.stringify(r.sent_via));
const derive = [
  ['x-client-info supabase-swift بلا x-app-platform (نسخة آيفون قديمة) → ios', { 'x-client-info': 'supabase-swift/2.5.1' }, 'ios'],
  ['supabase-flutter → android', { 'x-client-info': 'supabase-flutter/2.8.0' }, 'android'],
  ['supabase-dart → android', { 'x-client-info': 'supabase-dart/2.6.0' }, 'android'],
  ['supabase-js-web → web', { 'x-client-info': 'supabase-js-web/2.45.0' }, 'web'],
  ['supabase-js (قديم) → web', { 'x-client-info': 'supabase-js/2.39.0' }, 'web'],
  ['x-app-platform بحروف كبيرة', { 'x-app-platform': 'ANDROID', 'x-client-info': 'supabase-dart/2.6.0' }, 'android'],
  ['x-app-platform مجهول → من x-client-info', { 'x-app-platform': 'windows', 'x-client-info': 'supabase-swift/2.43.1' }, 'ios'],
  ['x-app-platform web من الموقع', { 'x-app-platform': 'web', 'x-client-info': 'supabase-js-web/2.45.0' }, 'web'],
  ['عميل مجهول (curl) → unknown', { 'user-agent': 'curl/8' }, 'unknown'],
];
for (const [label, h, want] of derive) {
  r = await send(P.M, path3, h);
  check(label, r.ok && r.sent_via?.platform === want, JSON.stringify(r.sent_via ?? r.err));
}
r = await send(P.M, path3, { ...IOS, 'x-app-version': "1.0;drop table", 'x-app-build': '1'.repeat(21) });
check('نسخة/بناء بحروف غير مقبولة أو أطول من ٢٠ → يُحذفان', r.ok && !('app_version' in r.sent_via) && !('app_build' in r.sent_via)
  && r.sent_via.platform === 'ios', JSON.stringify(r.sent_via));
r = await send(P.M, path3, { ...IOS, 'x-client-info': 'supabase-swift/2.43.1 ' + 'é'.repeat(5) + 'x'.repeat(80) });
check('العميل: ASCII مطبوع حتى ٦٠ حرفاً', r.ok && r.sent_via.client.length === 60 && !/é/.test(r.sent_via.client));
r = await send(P.M, path3, null);
check('بلا ترويسات (request.headers فارغ) → server + الوقت فقط', r.ok && r.sent_via.platform === 'server'
  && Object.keys(r.sent_via).sort().join() === 'at,platform', JSON.stringify(r.sent_via));
r = await send(P.M, path3, '{not json');
check('ترويسات فاسدة → server بلا رفض', r.ok && r.sent_via.platform === 'server', JSON.stringify(r.sent_via ?? r.err));
r = await send(P.M, path3, '[1,2]');
check('ترويسات ليست كائناً → server', r.ok && r.sent_via.platform === 'server');
await db.query(`select set_config('request.headers', '', false), set_config('request.jwt.claims', '', false)`);
let row = await one(`insert into admin_requests (member_id, requester_id, request_type, status, details, sent_from, sent_via)
  values ('${P.M}', '${P.M}', 'name_change', 'pending', 'صيانة', '[{"icon":"wrench","title":"صيانة"}]', '{"platform":"ios"}')
  returning sent_from, sent_via`);
check('صيانة SQL (بلا JWT ولا ترويسات): المسار يُنظَّف ويُحفظ، والجهاز server', row.sent_via.platform === 'server'
  && row.sent_from?.[0]?.title === 'صيانة', JSON.stringify(row));
r = await as('service', `insert into admin_requests (member_id, requester_id, request_type, status, details)
  values ('${P.M}', '${P.M}', 'name_change', 'pending', 'خدمة') returning sent_via`, [], IOS);
check('مفتاح الخدمة (دالة حافة) حتى بترويسات آيفون → server', r.ok && r.rows[0].sent_via.platform === 'server', JSON.stringify(r.rows?.[0] ?? r.err));
r = await as(P.M, `select public.test_rpc_relative_add() as id`, [], { 'x-client-info': 'supabase-flutter/2.8.0', 'x-app-version': '1.0.1', 'x-app-build': '49' });
row = r.ok ? await one(`select request_type, sent_from, sent_via from admin_requests where id = $1`, [r.rows[0].id]) : null;
check('طلب تُنشئه دالة سيرفر (relative_add): الجهاز من ترويسات الطلب، والمسار NULL', row?.request_type === 'relative_add'
  && row.sent_via.platform === 'android' && row.sent_via.app_version === '1.0.1' && row.sent_from === null, JSON.stringify(row ?? r.err));
r = await as(P.PEND, `insert into admin_requests (member_id, requester_id, request_type, status, details, sent_from)
  values ($1::uuid, $1::uuid, 'link_request', 'pending', 'طلب انضمام', $2::jsonb) returning sent_from, sent_via`,
  [P.PEND, JSON.stringify([{ icon: 'person.badge.plus', title: 'التسجيل' }])], IOS);
check('طلب انضمام من مسجّل معلّق: المسار والجهاز', r.ok && r.rows[0].sent_from[0].title === 'التسجيل' && r.rows[0].sent_via.platform === 'ios', r.err ?? '');
r = await as(P.A, `insert into admin_requests (member_id, requester_id, request_type, status, details, sent_from)
  values ($1::uuid, $1::uuid, 'tree_edit', 'approved', '{"action":"edit_name","targetMemberId":"${P.A}"}', $2::jsonb)
  returning sent_from, sent_via, replied_by`, [P.A, JSON.stringify([{ icon: 'person.fill', title: 'تعديل مباشر' }])], IOS);
check('سجلّ تعديل مباشر من الإدارة (معتمد عند الإدراج) يمرّ بمساره', r.ok && r.rows[0].sent_from[0].title === 'تعديل مباشر', r.err ?? '');
r = await send(P.M, path3, IOS, { admin_reply: 'مزيف' });
row = r.ok ? await one(`select status, admin_reply, replied_at, replied_by from admin_requests where id = $1`, [r.id]) : null;
check('حارس الإدراج كما هو: العضو لا يكتب ردّاً ولا حالة', row?.status === 'pending' && row.admin_reply === null && row.replied_at === null);

console.log('\n══════ ٤) لا يتغيّر المسار والجهاز بعد الإدراج — لأي أحد ══════');
const target = (await send(P.M, path3)).id;
const snap = async () => one(`select sent_from, sent_via from admin_requests where id = $1`, [target]);
const orig = JSON.stringify(await snap());
const tamper = `update admin_requests set sent_from = '[{"icon":"x","title":"مزوّر"}]', sent_via = '{"platform":"web"}',
  admin_reply = coalesce(admin_reply, '') || '.' where id = '${target}' returning admin_reply`;
r = await as(P.A, tamper);
check('المدير (authenticated): التحديث يمرّ والعمودان كما هما', r.ok && r.rows.length === 1 && JSON.stringify(await snap()) === orig, r.err ?? '');
r = await as(P.O, `update admin_requests set sent_from = null, sent_via = null where id = '${target}' returning id`);
check('المالك: تفريغهما لا يغيّرهما', r.ok && JSON.stringify(await snap()) === orig);
r = await as('service', tamper);
check('مفتاح الخدمة: العمودان كما هما', r.ok && JSON.stringify(await snap()) === orig);
r = await as('maint', tamper);
check('صيانة SQL: العمودان كما هما', r.ok && JSON.stringify(await snap()) === orig);
r = await as(P.M, tamper);
check('صاحب الطلب: سياسة الجدول تمنعه أصلاً (لا صفوف)', r.ok && r.rows.length === 0 && JSON.stringify(await snap()) === orig);
r = await as('maint', `insert into admin_requests (id, member_id, requester_id, request_type, status, details, sent_from)
  values ('${target}', '${P.M}', '${P.M}', 'name_change', 'pending', 'x', '[{"icon":"x","title":"y"}]')
  on conflict (id) do update set sent_from = excluded.sent_from, sent_via = excluded.sent_via, details = 'upsert' returning details`);
check('upsert على طلب قائم: يحدّث غيرهما ويبقيهما', r.ok && r.rows[0].details === 'upsert' && JSON.stringify(await snap()) === orig, r.err ?? '');

console.log('\n══════ ٥) من ردّ ومتى عند الإغلاق ══════');
const fresh = async (who = P.M) => (await send(who, path3)).id;
const closed = async rid => one(`select status, replied_by, replied_at is not null as has_at, admin_reply from admin_requests where id = $1`, [rid]);
let rid = await fresh();
r = await as(P.A, `update admin_requests set status = 'approved' where id = $1 and status = 'pending' returning id`, [rid]);
row = await closed(rid);
check('قبول مباشر من التطبيق (تفعيل الانضمام/الإشعار): replied_by = المدير وreplied_at', r.ok && row.replied_by === P.A && row.has_at, JSON.stringify(row));
rid = await fresh();
r = await as(P.MON, `update admin_requests set status = 'rejected', admin_reply = 'ناقص' where id = $1 returning id`, [rid]);
row = await closed(rid);
check('رفض المراقب بسبب: replied_by = المراقب والسبب كما هو', r.ok && row.replied_by === P.MON && row.has_at && row.admin_reply === 'ناقص', JSON.stringify(row));
rid = await fresh();
r = await as(P.O, `update admin_requests set status = 'approved', replied_by = '${P.A}', replied_at = '2026-01-01T00:00:00Z' where id = $1
  returning replied_by, replied_at`, [rid]);
check('ما يكتبه العميل صراحةً يبقى (أندرويد يرسل replied_by/replied_at)', r.ok && r.rows[0].replied_by === P.A
  && new Date(r.rows[0].replied_at).getUTCFullYear() === 2026 && new Date(r.rows[0].replied_at).getUTCMonth() === 0,
  r.err ?? JSON.stringify(r.rows[0]));
rid = await fresh();
r = await as(P.A, `select public.decide_admin_request($1::uuid, 'approve') as r`, [rid]);
row = await closed(rid);
check('decide_admin_request (قبول تغيير الاسم): replied_by = المدير', r.ok && row.status === 'approved' && row.replied_by === P.A && row.has_at,
  r.err ?? JSON.stringify(row));
rid = await fresh();
r = await as(P.A, `select public.decide_admin_request($1::uuid, 'reject', 'غير صحيح') as r`, [rid]);
row = await closed(rid);
check('decide_admin_request (رفض): replied_by = المدير', r.ok && row.status === 'rejected' && row.replied_by === P.A, r.err ?? JSON.stringify(row));
rid = await fresh();
r = await as('maint', `update admin_requests set status = 'approved' where id = $1 returning id`, [rid]);
row = await closed(rid);
check('صيانة SQL: replied_at فقط (لا ملف متصل)', r.ok && row.replied_by === null && row.has_at, JSON.stringify(row));
rid = await fresh();
r = await as('service', `update admin_requests set status = 'rejected' where id = $1 returning id`, [rid]);
row = await closed(rid);
check('مفتاح الخدمة: replied_at فقط', r.ok && row.replied_by === null && row.has_at);
rid = await fresh();
r = await as(P.A, `update admin_requests set admin_reply = 'قيد المتابعة' where id = $1 returning id`, [rid]);
row = await closed(rid);
check('تحديث لا يُغلق الطلب (رد مبدئي): لا تعبئة', r.ok && row.status === 'pending' && row.replied_by === null && !row.has_at);
await as(P.A, `update admin_requests set status = 'approved' where id = $1`, [rid]);
const firstAt = (await one(`select replied_at from admin_requests where id = $1`, [rid])).replied_at;
r = await as(P.O, `update admin_requests set admin_reply = 'ملاحظة لاحقة' where id = $1 returning replied_by`, [rid]);
row = await one(`select replied_by, replied_at from admin_requests where id = $1`, [rid]);
check('بعد الإغلاق: تحديث لاحق لا يغيّر من ردّ ومتى', r.ok && row.replied_by === P.A && String(row.replied_at) === String(firstAt));
// متصل بلا ملف (JWT لمستخدم بلا profiles) — لا يكسر المفتاح الأجنبي
await db.exec(`insert into auth.users(id) values ('${id(99)}')`);
await db.exec(`create policy t_upd_any on public.admin_requests as permissive for update to authenticated using (auth.uid() = '${id(99)}');
  create policy t_sel_any on public.admin_requests as permissive for select to authenticated using (auth.uid() = '${id(99)}')`);
rid = await fresh();
r = await as(id(99), `update admin_requests set status = 'approved' where id = $1 returning replied_by`, [rid]);
check('متصل بلا ملف: لا replied_by (المفتاح الأجنبي سليم) والإغلاق يمرّ', r.ok && r.rows[0]?.replied_by === null, r.err ?? JSON.stringify(r.rows));
await db.exec(`drop policy t_upd_any on public.admin_requests; drop policy t_sel_any on public.admin_requests`);

console.log('\n══════ ٦) مسار الموافقات شغّال: الإغلاق بالمسار يسجّل من نفّذ ══════');
await db.exec(`update app_settings set approvals_workflow = true`);
r = await send(P.M, path3);
const wid = r.id;
check('الطلب يدخل المسار والمسار/الجهاز محفوظان', r.ok && (await one(`select stage from admin_requests where id = $1`, [wid])).stage === 'review'
  && r.sent_from.length === 3 && r.sent_via.platform === 'ios');
const adv = (who, a) => as(who, `select public.advance_admin_request($1::uuid, $2, 'ملاحظة') as r`, [wid, a]);
r = await adv(P.MON, 'recommend_approve');
check('المراقب يوصي (advance_admin_request) — العمودان كما هما', r.ok && (await one(`select sent_from from admin_requests where id = $1`, [wid])).sent_from.length === 3, r.err ?? '');
r = await adv(P.A, 'approve');
check('المدير يعتمد', r.ok, r.err ?? '');
r = await as(P.MON, `update admin_requests set status = 'approved' where id = $1 returning approved_by, replied_by`, [wid]);
check('المراقب ينفّذ: approved_by = المدير (المسار) وreplied_by = المراقب (المشغّل الجديد)',
  r.ok && r.rows[0].approved_by === P.A && r.rows[0].replied_by === P.MON, r.err ?? JSON.stringify(r.rows[0]));
await db.exec(`update app_settings set approvals_workflow = false`);

console.log('\n══════ ٧) «ما تم في الطلب»: سجلّ لكل تغيير ومن فعله ══════');
await clean();
let e1 = (await send(P.M, path3)).id;
let ev = await events(e1);
check('الإرسال: sent بهوية المرسل ودوره', ev.length === 1 && ev[0].action === 'sent' && ev[0].actor_id === P.M && ev[0].actor_role === 'member',
  JSON.stringify(ev));
await as(P.A, `update admin_requests set admin_reply = 'نراجعه' where id = $1`, [e1]);
await as(P.A, `update admin_requests set status = 'approved' where id = $1`, [e1]);
ev = await events(e1);
check('رد بلا إغلاق ثم قبول: replied ثم approved بهوية المدير والملاحظة', (await acts(e1)) === 'sent,replied,approved'
  && ev[1].actor_id === P.A && ev[1].note === 'نراجعه' && ev[2].actor_id === P.A && ev[2].actor_role === 'admin', JSON.stringify(ev));
e1 = (await send(P.M, path3)).id;
await as(P.MON, `update admin_requests set status = 'rejected', admin_reply = 'الاسم غير مطابق' where id = $1`, [e1]);
ev = await events(e1);
check('رفض المراقب بسبب: rejected + السبب + المراقب', ev.at(-1).action === 'rejected' && ev.at(-1).actor_id === P.MON
  && ev.at(-1).actor_role === 'monitor' && ev.at(-1).note === 'الاسم غير مطابق');
await as(P.A, `update admin_requests set status = 'pending' where id = $1`, [e1]);
check('إعادة فتح: reopened', (await acts(e1)).endsWith('rejected,reopened'));
e1 = (await send(P.M, path3)).id;
await as(P.A, `select public.decide_admin_request($1::uuid, 'approve')`, [e1]);
ev = await events(e1);
check('decide_admin_request: approved بهوية المدير', ev.at(-1).action === 'approved' && ev.at(-1).actor_id === P.A, JSON.stringify(ev));
e1 = (await send(P.M, path3)).id;
await as('maint', `update admin_requests set status = 'approved' where id = $1`, [e1]);
ev = await events(e1);
check('صيانة SQL: approved بلا هوية ودور server', ev.at(-1).action === 'approved' && ev.at(-1).actor_id === null && ev.at(-1).actor_role === 'server');
r = await as(P.M, `insert into admin_requests (member_id, requester_id, request_type, status, new_value, details)
  values ($1::uuid, $1::uuid, 'contact_message', 'pending', 'استفسار', 'التصنيف: استفسار\nالرسالة: …') returning id`, [P.M], IOS);
e1 = r.rows[0].id;
await as(P.O, `update admin_requests set status = 'approved', admin_reply = 'تم الرد' where id = $1`, [e1]);
check('رسالة تواصل: replied (لا approved) بهوية المالك', (await acts(e1)) === 'sent,replied'
  && (await events(e1)).at(-1).actor_role === 'owner' && (await events(e1)).at(-1).note === 'تم الرد');
e1 = (await send(P.M, path3)).id;
r = await as(P.M, `delete from admin_requests where id = $1 returning id`, [e1]);
check('صاحب الطلب يسحبه: withdrawn ويبقى السجل بعد الحذف', r.ok && r.rows.length === 1 && (await acts(e1)) === 'sent,withdrawn', r.err ?? (await acts(e1)));
e1 = (await send(P.M, path3)).id;
r = await as(P.O, `delete from admin_requests where id = $1 returning id`, [e1]);
check('المالك يحذفه: deleted بهوية المالك', r.ok && (await acts(e1)) === 'sent,deleted' && (await events(e1)).at(-1).actor_id === P.O);
// مسار الموافقات: كل مرحلة بمن فعلها
await db.exec(`update app_settings set approvals_workflow = true`);
e1 = (await send(P.M, path3)).id;
await as(P.MON, `select public.advance_admin_request($1::uuid, 'recommend_approve', 'مطابق')`, [e1]);
await as(P.A, `select public.advance_admin_request($1::uuid, 'return', 'راجعه مرة أخرى')`, [e1]);
await as(P.MON, `select public.advance_admin_request($1::uuid, 'recommend_approve', 'مطابق')`, [e1]);
await as(P.A, `select public.advance_admin_request($1::uuid, 'approve', 'موافق')`, [e1]);
await as(P.MON, `update admin_requests set status = 'approved' where id = $1`, [e1]);
ev = await events(e1);
const want = 'sent,recommended_approve,returned,recommended_approve,manager_approved,executed';
check('مسار الموافقات: توصية ← إرجاع ← توصية ← اعتماد ← تنفيذ، كلٌّ بمن فعله وملاحظته',
  ev.map(e => e.action).join(',') === want
  && ev.find(e => e.action === 'manager_approved')?.actor_id === P.A && ev.at(-1).actor_id === P.MON
  && ev[1].note === 'مطابق' && ev[2].actor_id === P.A, ev.map(e => `${e.action}/${e.actor_role}`).join(','));
e1 = (await send(P.M, path3)).id;
r = await as(P.MON, `select public.advance_admin_request($1::uuid, 'request_info', 'أرسل صورة الهوية')`, [e1]);
ev = await events(e1);
check('طلب معلومات: info_requested بالنص', r.ok && ev.at(-1).action === 'info_requested' && ev.at(-1).note === 'أرسل صورة الهوية'
  && ev.at(-1).actor_id === P.MON, r.err ?? JSON.stringify(ev));
e1 = (await send(P.M, path3)).id;
r = await as(P.MON, `select public.advance_admin_request($1::uuid, 'claim')`, [e1]);
await as(P.MON, `select public.advance_admin_request($1::uuid, 'release')`, [e1]);
check('استلام وترك: claimed ثم released بهوية المراقب', r.ok && (await acts(e1)) === 'sent,claimed,released'
  && (await events(e1)).at(-1).actor_id === P.MON, r.err ?? (await acts(e1)));
await db.exec(`update app_settings set approvals_workflow = false`);
// قبول الانضمام بتفعيل الحساب (الآيفون: profiles ثم إغلاق الطلب)
r = await as(P.PEND, `insert into admin_requests (member_id, requester_id, request_type, status, details)
  values ($1::uuid, $1::uuid, 'link_request', 'pending', 'طلب انضمام') returning id`, [P.PEND], IOS);
const jr = r.rows[0].id;
r = await as(P.A, `update profiles set status = 'active', role = 'member' where id = $1 returning id`, [P.PEND]);
await as(P.A, `update admin_requests set status = 'approved' where member_id = $1 and request_type in ('join_request', 'link_request')
  and status = 'pending'`, [P.PEND]);
ev = await events(jr);
check('قبول الانضمام: member_activated (من تحديث الملف) ثم approved — كلاهما بهوية المدير',
  r.ok && ev.map(e => e.action).join(',') === 'sent,member_activated,approved' && ev[1].actor_id === P.A && ev[2].actor_id === P.A,
  r.err ?? JSON.stringify(ev));
await db.exec(`update profiles set status = 'pending', role = 'pending' where id = '${P.PEND}'`);
const nEv = (await one(`select count(*)::int n from admin_request_events`)).n;
await db.exec(`update profiles set status = 'active', role = 'member' where id = '${P.PEND}'`);
check('تفعيل بلا مستخدم من الإدارة (صيانة/أول دخول): لا يُسجَّل قبولاً', (await one(`select count(*)::int n from admin_request_events`)).n === nEv);
await db.exec(`update profiles set status = 'pending', role = 'pending' where id = '${P.PEND}'`);
// القراءة والكتابة
e1 = (await send(P.M, path3)).id;
r = await as(P.M, `select count(*)::int n from admin_request_events`);
check('العضو لا يقرأ السجل', r.ok && r.rows[0].n === 0);
r = await as(P.MON, `select count(*)::int n from admin_request_events where request_id = $1`, [e1]);
check('المراقب يقرأ سجلّ طلب من مجاله', r.ok && r.rows[0].n === 1);
r = await as(id(3) /* لا ملف */, `select count(*)::int n from admin_request_events`);
check('بلا دور: لا شيء', r.ok && r.rows[0].n === 0);
for (const [who, sql] of [[P.O, `insert into admin_request_events (request_id, action) values ('${e1}', 'approved')`],
                          [P.O, `update admin_request_events set actor_id = null`],
                          [P.O, `delete from admin_request_events`]]) {
  r = await as(who, sql);
  check(`لا كتابة مباشرة للسجل حتى للمالك: ${sql.split(' ')[0]}`, !r.ok, r.err ?? 'مرّ!');
}

console.log('\n══════ ٨) التراجع ══════');
await clean();
await db.exec(rollback);
check('التراجع يعيد شكل الجدول والمشغّلات والدوال والسياسات والصلاحيات حرفياً', (await shape()) === before);
await db.exec(rollback);
check('التراجع يُعاد بلا خطأ', true);
r = await send(P.M, undefined);
check('بعد التراجع: الطلب العادي يمرّ', r.ok, r.err ?? '');
await db.exec(mig);
check('إعادة التطبيق بعد التراجع = الشكل نفسه', (await shape()) === once);

console.log('\n══════ ٩) التجارب القائمة كاملة والترحيل مثبّت ══════');
function replay(file, swaps, label, allowFail = []) {
  let src = readFileSync(HERE + file, 'utf8');
  for (const [anchor, add, prepend] of swaps) {
    if (!src.includes(anchor)) { check(`${label}: نقطة الحقن موجودة`, false, anchor); return; }
    src = src.replace(anchor, () => prepend ? `${add}\n${anchor}` : `${anchor}\n${add}`);
  }
  const tmp = `${HERE}.sent_info_replay_${file}`;
  writeFileSync(tmp, src);
  try {
    const run = spawnSync(process.execPath, [tmp], { cwd: HERE, encoding: 'utf8', maxBuffer: 64 << 20 });
    const summary = (run.stdout.match(/النتيجة: \d+ نجح، \d+ فشل/g) ?? ['']).at(-1);
    const failed = run.stdout.split('\n').filter(l => l.startsWith('❌'));
    const unexpected = failed.filter(l => !allowFail.some(a => l.includes(a)));
    const ok = run.status === 0 || (failed.length > 0 && unexpected.length === 0 && /النتيجة/.test(run.stdout));
    check(label, ok, summary + (unexpected.length ? ' ' + unexpected.slice(0, 5).join(' | ') : '')
      + (failed.length && !unexpected.length ? ' (فشل قائم قبل الترحيل: ' + failed.length + ')' : '')
      + (!ok && run.status ? ' ' + run.stderr.slice(-600) : ''));
  } finally { unlinkSync(tmp); }
}
const ex = sql => `await db.exec(${JSON.stringify(sql)});`;
replay('admin_requests_guard.test.mjs', [['if (withGuard) await db.exec(guard);', ex(mig)]],
  'admin_requests_guard.test.mjs كاملة والترحيل مثبّت (قبل الحارس وبعده وبعد تراجعه)');
replay('decide_admin_request.test.mjs', [['await db.exec(live); await db.exec(guard); await db.exec(mig);', ex(mig)]],
  'decide_admin_request.test.mjs كاملة والترحيل مثبّت');
// قبل لقطة «قبل المسار» — فتراجعات المسار تعود إلى حالة فيها هذا الترحيل
replay('approvals_workflow.test.mjs', [['const before = await shape();', ex(mig), true]],
  'approvals_workflow.test.mjs كاملة والترحيل مثبّت');
// (لا تشغّل هذه التجربة بالتوازي مع approvals_*: إعاداتها المتداخلة تكتب ملفات مؤقتة بالاسم نفسه)
replay('approvals_v2.test.mjs', [['await db.exec(wfMig); await db.exec(ownerFix); await db.exec(infoMig); await db.exec(delFix);', ex(mig)]],
  'approvals_v2.test.mjs كاملة والترحيل مثبّت');

console.log(`\nالنتيجة: ${pass} نجح، ${fail} فشل`);
process.exit(fail ? 1 : 0);
