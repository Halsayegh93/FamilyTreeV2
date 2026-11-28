// تجربة 20261108120000_lineage_request_details على قاعدة محلية معزولة (لا تلمس السيرفر):
//   «طلب نسب» كامل للإدارة — الصلاحية (المالك والمدير والمراقب فقط)، اسمه ورقمه كاملاً ومتى سجّل، سلسلة الأم
//   (بنت من العائلة أو «أم جديدة»)، الأب (المسجّل أو المكتوب) حي/متوفى، من أرسل ومن وافق، والأجهزة (الأقدم أولاً)، ثم التراجع.
// التشغيل: cd supabase/tests/family_links && node lineage_request_details.test.mjs
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
const lineage = readFileSync(`${REPO}/migrations/20261107120000_daughter_sons_lineage.sql`, 'utf8');
const restricted = readFileSync(`${REPO}/migrations/20261108090000_daughter_sons_restricted.sql`, 'utf8');
const mig = readFileSync(`${REPO}/migrations/20261108120000_lineage_request_details.sql`, 'utf8');
const undo = readFileSync(`${REPO}/rollback/20261108120000_lineage_request_details_rollback.sql`, 'utf8');
const prevTest = readFileSync(new URL('./daughter_sons_lineage.test.mjs', import.meta.url), 'utf8');
const live = prevTest.slice(prevTest.indexOf('const live = `') + 'const live = `'.length, prevTest.indexOf('`;', prevTest.indexOf('const live = `')));

// ما يحتاجه 20261108090000 (الأقسام المقفولة) + أعمدة device_tokens كالحي
const extras = `
create schema if not exists private;
create table public.diwaniyas (id uuid primary key default gen_random_uuid(), name text);
create table public.projects (id uuid primary key default gen_random_uuid(), title text);
create table public.family_archive (id uuid primary key default gen_random_uuid(), title text);
alter table public.device_tokens add column platform text, add column device_name text, add column app_version text,
  add column app_build int, add column created_at timestamptz default now(), add column updated_at timestamptz default now();`;

const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
// O مالك · A مدير · MON مراقب · SUP مشرف · M عضو · GP محمد (جد) · F عبدالله بن محمد · G سعود بن محمد
// D1/D2 بنتا عبدالله · SON/SON2/SON3 أبناء بنات
const P = { O: id(1), MON: id(2), A: id(3), M: id(4), F: id(5), G: id(6), SUP: id(8), GP: id(9), D1: id(10), D2: id(11),
  SON: id(20), SON2: id(21), SON3: id(22) };
let pass = 0, fail = 0;
const check = (l, ok, x = '') => { ok ? pass++ : fail++; console.log(`${ok ? '✅' : '❌'} ${l}${x ? ' — ' + x : ''}`); };

const db = new PGlite();
await db.exec(baseBody); await db.exec(preFns); await db.exec(baseTriggers); await db.exec(live); await db.exec(extras);
await db.exec(`
  insert into profiles(id, first_name, full_name, gender, role, status, phone_number, is_phone_hidden, registration_platform) values
    ('${P.O}', 'مالك', 'المالك', 'male', 'owner', 'active', null, false, 'ios'),
    ('${P.A}', 'مدير', 'المدير', 'male', 'admin', 'active', null, false, 'ios'),
    ('${P.MON}', 'مراقب', 'المراقب', 'male', 'monitor', 'active', null, false, 'ios'),
    ('${P.SUP}', 'مشرف', 'المشرف', 'male', 'supervisor', 'active', null, false, 'ios'),
    ('${P.M}', 'عضو', 'عضو', 'male', 'member', 'active', null, false, 'ios'),
    ('${P.GP}', 'محمد', 'محمد المحمدعلي', 'male', 'member', 'active', null, false, 'ios'),
    ('${P.F}', 'عبدالله', 'عبدالله محمد المحمدعلي', 'male', 'member', 'active', null, false, 'ios'),
    ('${P.G}', 'سعود', 'سعود محمد المحمدعلي', 'male', 'member', 'active', null, false, 'ios'),
    ('${P.SON}', 'سالم', 'سالم فهد العتيبي', 'male', 'pending', 'pending', '+96555000001', true, 'android'),
    ('${P.SON2}', 'ماجد', 'ماجد خالد العتيبي', 'male', 'pending', 'pending', '+96555000002', false, 'ios'),
    ('${P.SON3}', 'بدر', 'بدر سعد العتيبي', 'male', 'pending', 'pending', '+96555000003', false, 'ios');
  insert into women_members(id, first_name, full_name, gender) values ('${P.GP}', 'محمد', 'محمد المحمدعلي', 'male') on conflict do nothing;
  update profiles set father_id = '${P.GP}' where id in ('${P.F}', '${P.G}');
  insert into women_members(id, first_name, full_name, gender) values
    ('${P.F}', 'عبدالله', 'عبدالله محمد المحمدعلي', 'male') on conflict do nothing;
  insert into women_members(id, first_name, full_name, parent_id, gender) values
    ('${P.D1}', 'نورة', 'نورة عبدالله محمد المحمدعلي', '${P.F}', 'female'),
    ('${P.D2}', 'هيا', 'هيا عبدالله محمد المحمدعلي', '${P.F}', 'female');
  insert into admin_requests(member_id, requester_id, request_type, status, created_at) values
    ('${P.SON}', '${P.SON}', 'join_request', 'pending', now() - interval '3 days'),
    ('${P.SON2}', '${P.SON2}', 'join_request', 'pending', now() - interval '2 days'),
    ('${P.SON3}', '${P.M}', 'join_request', 'pending', now() - interval '1 days');
  insert into auth.users(id) values ('${P.O}'), ('${P.A}'), ('${P.MON}'), ('${P.SUP}'), ('${P.M}'),
    ('${P.SON}'), ('${P.SON2}'), ('${P.SON3}');
  insert into device_tokens(member_id, token, platform, device_name, app_version, app_build, created_at) values
    ('${P.SON}', 't2', 'ios', 'iPhone سالم', '1.0.0', 50, now() - interval '1 days'),
    ('${P.SON}', 't1', 'android', 'Galaxy S24', '1.0.0', 48, now() - interval '3 days');`);
await db.exec(lineage); await db.exec(restricted);

async function as(who, sql, params = []) {
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [JSON.stringify({ sub: who, role: 'authenticated' })]);
  await db.exec('set role authenticated');
  try { return { ok: true, rows: (await db.query(sql, params)).rows }; }
  catch (e) { return { ok: false, err: e.message, hint: e.hint }; }
  finally { await db.exec('reset role'); }
}
const one = async (sql, p = []) => (await db.query(sql, p)).rows[0];
const details = async (who, rid) => { const r = await as(who, `select public.lineage_request_details($1) as r`, [rid]); return r.ok ? { ok: true, d: r.rows[0].r } : r; };
const submit = (who, a) => as(who, `select public.submit_daughter_son_lineage(
    p_mother_id => $1, p_father_id => $2, p_father_full_name => $3, p_father_deceased => $4,
    p_new_mother_name => $5, p_new_mother_father_id => $6, p_new_mother_deceased => $7) as id`,
  [a.mother ?? null, a.father ?? null, a.line ?? null, a.dead ?? false, a.newName ?? null, a.newFather ?? null, a.newDead ?? false]);

await as(P.MON, `select public.approve_join_as_daughter_son($1)`, [P.SON]);
await as(P.O, `select public.approve_join_as_daughter_son($1)`, [P.SON2]);
await as(P.A, `select public.approve_join_as_daughter_son($1)`, [P.SON3]);
let r = await submit(P.SON, { mother: P.D1, line: 'فهد ناصر العتيبي', dead: true });
const rid1 = r.rows?.[0]?.id;
check('تجهيز: طلب نسب بأم من بنات العائلة', r.ok && !!rid1, r.err);

r = await details(P.O, rid1);
check('قبل الترحيل: الدالة غير موجودة (التطبيقات ترجع لبطاقة اليوم)', !r.ok);

await db.exec(mig);
console.log('\n══════ بعد الإضافة ══════');

// ── الصلاحية ──
for (const [who, label] of [[P.M, 'العضو'], [P.SUP, 'المشرف'], [P.SON, 'صاحب الطلب نفسه']]) {
  r = await details(who, rid1);
  check(`${label} مرفوض (not_allowed)`, !r.ok && r.hint === 'not_allowed', r.hint ?? 'سُمح');
}
r = await as(P.MON, `select public.lineage_request_details(id) r from admin_requests where request_type = 'join_request' limit 1`);
check('طلب ليس «طلب نسب» → request_not_found', !r.ok && r.hint === 'request_not_found', r.hint);
r = await details(P.MON, id(999));
check('طلب غير موجود → request_not_found', !r.ok && r.hint === 'request_not_found', r.hint);
const asSystem = sql => db.exec(`select set_config('request.jwt.claims', '', false); ${sql}`);
await asSystem(`update profiles set status = 'frozen' where id = '${P.A}'`);
r = await details(P.A, rid1);
check('المدير الموقوف مرفوض', !r.ok && r.hint === 'not_allowed', r.hint);
await asSystem(`update profiles set status = 'active' where id = '${P.A}'`);

// ── المراقب: كل التفاصيل ──
r = await details(P.MON, rid1);
let d = r.d;
check('المراقب يقرأ', r.ok, r.err);
check('اسمه الكامل + رقمه كاملاً (ولو مخفياً عن الأعضاء)', d?.member?.full_name === 'سالم فهد العتيبي'
  && d?.member?.phone === '+96555000001' && d?.member?.phone_hidden === true, JSON.stringify(d?.member));
check('متى سجّل + منصة التسجيل', !!d?.member?.registered_at && d?.member?.registration_platform === 'android');
check('الأم: بنت من العائلة واسمها الكامل', d?.mother?.is_new === false && d?.mother?.id === P.D1
  && d?.mother?.name === 'نورة عبدالله محمد المحمدعلي', JSON.stringify(d?.mother));
check('سلسلة الأم: نورة · عبدالله · محمد', JSON.stringify(d?.mother?.chain) === JSON.stringify(['نورة', 'عبدالله', 'محمد']),
  JSON.stringify(d?.mother?.chain));
check('أبوها وجدها بأسمائهم الكاملة', d?.mother?.father?.name === 'عبدالله محمد المحمدعلي'
  && d?.mother?.grandfather?.name === 'محمد المحمدعلي');
check('الأب: مكتوب، من خارج العائلة، متوفى', d?.father?.registered === false && d?.father?.name === 'فهد ناصر العتيبي'
  && d?.father?.is_deceased === true && d?.father?.is_outside_family === true, JSON.stringify(d?.father));
check('أرسل الطلب: هو نفسه', d?.requester?.id === P.SON && d?.requester?.is_self === true);
check('طلب الانضمام: أرسله هو، وردّ عليه المراقب', d?.join?.type === 'join_request' && d?.join?.requester?.is_self === true
  && d?.join?.replied_by?.name === 'المراقب', JSON.stringify(d?.join));
check('وافق عليه «ابن بنت»: المراقب', d?.lineage?.approved_by?.id === P.MON && d?.lineage?.approved_by?.role === 'monitor'
  && !!d?.lineage?.approved_at && d?.lineage?.completed_at === null);
check('الأجهزة: الأقدم أولاً (Galaxy ثم iPhone)', d?.device_count === 2 && d?.devices?.length === 2
  && d?.devices?.[0]?.device_name === 'Galaxy S24' && d?.devices?.[1]?.platform === 'ios', JSON.stringify(d?.devices));
check('أول جهاز سجّل منه: أندرويد · النسخة والبناء', d?.first_device?.platform === 'android'
  && d?.first_device?.app_version === '1.0.0' && d?.first_device?.app_build === 48 && !!d?.first_device?.created_at);
check('الطلب نفسه: الحالة والملخّص', d?.request?.status === 'pending' && /نورة/.test(d?.request?.summary ?? ''));
r = await details(P.O, rid1);
check('المالك يقرأ نفس الشي', r.ok && r.d?.member?.phone === '+96555000001');
r = await details(P.A, rid1);
check('المدير يقرأ', r.ok && r.d?.mother?.id === P.D1);

// ── «أم جديدة» + بلا أجهزة ──
r = await submit(P.SON2, { newName: 'منيرة', newFather: P.G, newDead: true, line: 'خالد سعد العتيبي' });
const rid2 = r.rows?.[0]?.id;
r = await details(P.MON, rid2);
d = r.d;
check('أم جديدة: الاسم المكتوب + متوفاة', r.ok && d?.mother?.is_new === true && d?.mother?.id === null
  && d?.mother?.name === 'منيرة' && d?.mother?.is_deceased === true, JSON.stringify(d?.mother));
check('أم جديدة: سلسلة أبيها المختار (منيرة · سعود · محمد)',
  JSON.stringify(d?.mother?.chain) === JSON.stringify(['منيرة', 'سعود', 'محمد']), JSON.stringify(d?.mother?.chain));
check('أم جديدة: أبوها وجدها', d?.mother?.father?.id === P.G && d?.mother?.father?.name === 'سعود محمد المحمدعلي'
  && d?.mother?.grandfather?.id === P.GP);
check('الأب المكتوب حي', d?.father?.registered === false && d?.father?.is_deceased === false);
check('بلا أجهزة: [] و first_device = null', Array.isArray(d?.devices) && d.devices.length === 0 && d?.first_device == null
  && d?.device_count === 0);
check('وافق عليه «ابن بنت»: المالك', d?.lineage?.approved_by?.name === 'المالك');

// ── أب مسجّل (زوج من خارج العائلة) + طلب انضمام أرسله غيره ──
r = await as(P.O, `select public.add_outside_husband($1, 'سعد ناصر العتيبي', true) as h`, [P.D2]);
const hid = r.rows?.[0]?.h;
r = await submit(P.SON3, { mother: P.D2, father: hid });
const rid3 = r.rows?.[0]?.id;
r = await details(P.MON, rid3);
d = r.d;
check('الأب المسجّل: اسمه من شجرة النساء + متوفى', r.ok && d?.father?.registered === true && d?.father?.id === hid
  && d?.father?.name === 'سعد ناصر العتيبي' && d?.father?.is_deceased === true && d?.father?.is_outside_family === true,
  JSON.stringify(d?.father));
check('طلب الانضمام أرسله غيره (عضو)', d?.join?.requester?.id === P.M && d?.join?.requester?.is_self === false
  && d?.join?.requester?.name === 'عضو', JSON.stringify(d?.join?.requester));
check('وافق عليه المدير', d?.lineage?.approved_by?.role === 'admin');

// ── بعد القرار: يبقى يُقرأ ──
await as(P.O, `select public.decide_lineage_request($1, 'approve', null)`, [rid1]);
r = await details(P.MON, rid1);
check('بعد الموافقة: الحالة approved واكتمل', r.ok && r.d?.request?.status === 'approved' && !!r.d?.lineage?.completed_at);

// ── حمولة تالفة ──
await asSystem(`update admin_requests set details = 'not json' where id = '${rid2}'`);
r = await details(P.MON, rid2);
check('حمولة تالفة: لا خطأ، الأم والأب فارغان', r.ok && r.d?.member?.full_name === 'ماجد خالد العتيبي'
  && r.d?.father?.name === null && JSON.stringify(r.d?.mother?.chain) === '[]' && r.d?.mother?.is_new === false, r.err ?? JSON.stringify(r.d?.mother));

// ── لا تنفيذ لـ anon ──
check('anon بلا تنفيذ', (await one(`select has_function_privilege('anon', 'public.lineage_request_details(uuid)', 'execute') v`)).v === false);

await db.exec(undo);
console.log('\n══════ بعد التراجع ══════');
r = await details(P.O, rid1);
check('الدالة حُذفت', !r.ok);

console.log(`\n${pass} نجح · ${fail} فشل`);
process.exit(fail ? 1 : 0);
