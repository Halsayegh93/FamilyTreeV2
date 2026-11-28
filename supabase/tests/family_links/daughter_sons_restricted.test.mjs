// تجربة 20261108090000_daughter_sons_restricted على قاعدة محلية معزولة (لا تلمس السيرفر):
//   «أكمل حسابك» — القفل على السيرفر (lineage_locked + RESTRICTIVE)، البحث بلا تصفّح (الاسم الثلاثي)، «اسم الأب الكامل»
//   سطراً واحداً (والحقول الأربعة القديمة)، «ما لقيت أمي؟» (أم جديدة تحت أبيها)، نصوص الإشعارات، ثم التراجع.
// التشغيل: cd supabase/tests/family_links && node daughter_sons_restricted.test.mjs
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
const fix = readFileSync(`${REPO}/migrations/20261108090000_daughter_sons_restricted.sql`, 'utf8');
const undo = readFileSync(`${REPO}/rollback/20261108090000_daughter_sons_restricted_rollback.sql`, 'utf8');
// ما يعتمد عليه 20261107120000 كما في السيرفر الحي — من تجربته نفسها (مصدر واحد)
const prevTest = readFileSync(new URL('./daughter_sons_lineage.test.mjs', import.meta.url), 'utf8');
const live = prevTest.slice(prevTest.indexOf('const live = `') + 'const live = `'.length, prevTest.indexOf('`;', prevTest.indexOf('const live = `')));

// الأقسام المقفولة (نسخ مصغّرة) وسياسات قراءة متساهلة كالحي، وRLS على شجرة النساء
const sections = `
create schema if not exists private;
create table public.diwaniyas (id uuid primary key default gen_random_uuid(), name text);
create table public.projects (id uuid primary key default gen_random_uuid(), title text);
create table public.family_archive (id uuid primary key default gen_random_uuid(), title text);
alter table public.diwaniyas enable row level security;
alter table public.projects enable row level security;
alter table public.family_archive enable row level security;
alter table public.women_members enable row level security;
create policy d_sel on public.diwaniyas for select to authenticated using (auth.uid() is not null);
create policy p_sel on public.projects for select to authenticated using (auth.uid() is not null);
create policy a_sel on public.family_archive for select to authenticated using (auth.uid() is not null);
create policy w_sel on public.women_members for select to authenticated using (true);
create policy w_all on public.women_members for all to postgres using (true);
grant select on public.diwaniyas, public.projects, public.family_archive to authenticated;
insert into public.diwaniyas(name) values ('ديوانية'); insert into public.projects(title) values ('مشروع');
insert into public.family_archive(title) values ('وثيقة');`;

const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
// O مالك · MON مراقب · M عضو · F أب في الشجرة (ونسخته في شجرة النساء) · G رجل في الشجرة بلا نسخة نساء (جذر)
// PEND حساب معلّق · D1/D2 بنتا F بلا زوج · DH بنت مخفية · SON/SON2/SON3 أبناء بنات
const P = { O: id(1), MON: id(2), M: id(4), F: id(5), G: id(6), PEND: id(7), D1: id(10), D2: id(11), DH: id(12),
  SON: id(20), SON2: id(21), SON3: id(22) };
let pass = 0, fail = 0;
const check = (l, ok, x = '') => { ok ? pass++ : fail++; console.log(`${ok ? '✅' : '❌'} ${l}${x ? ' — ' + x : ''}`); };

const db = new PGlite();
await db.exec(baseBody); await db.exec(preFns); await db.exec(baseTriggers); await db.exec(live); await db.exec(sections);
await db.exec(`
  insert into profiles(id, first_name, full_name, gender, role, status) values
    ('${P.O}', 'مالك', 'المالك', 'male', 'owner', 'active'),
    ('${P.MON}', 'مراقب', 'المراقب', 'male', 'monitor', 'active'),
    ('${P.M}', 'عضو', 'عضو', 'male', 'member', 'active'),
    ('${P.F}', 'عبدالله', 'عبدالله محمد المحمدعلي', 'male', 'member', 'active'),
    ('${P.G}', 'سعود', 'سعود محمد المحمدعلي', 'male', 'member', 'active'),
    ('${P.PEND}', 'سعود', 'سعود محمد المحمدعلي الثاني', 'male', 'pending', 'pending'),
    ('${P.SON}', 'سالم', 'سالم فهد العتيبي', 'male', 'pending', 'pending'),
    ('${P.SON2}', 'ماجد', 'ماجد العتيبي', 'male', 'pending', 'pending'),
    ('${P.SON3}', 'بدر', 'بدر العتيبي', 'male', 'pending', 'pending');
  insert into women_members(id, first_name, full_name, gender) values
    ('${P.F}', 'عبدالله', 'عبدالله محمد المحمدعلي', 'male') on conflict do nothing;
  insert into women_members(id, first_name, full_name, parent_id, gender, is_hidden_from_tree) values
    ('${P.D1}', 'نورة', 'نورة عبدالله محمد المحمدعلي', '${P.F}', 'female', false),
    ('${P.D2}', 'هيا', 'هيا عبدالله محمد المحمدعلي', '${P.F}', 'female', false),
    ('${P.DH}', 'نوف', 'نوف عبدالله محمد المحمدعلي', '${P.F}', 'female', true);
  insert into admin_requests(member_id, requester_id, request_type, status) values
    ('${P.SON}', '${P.SON}', 'join_request', 'pending'), ('${P.SON2}', '${P.SON2}', 'join_request', 'pending'),
    ('${P.SON3}', '${P.SON3}', 'join_request', 'pending');
  insert into auth.users(id) values ('${P.O}'), ('${P.MON}'), ('${P.M}'), ('${P.SON}'), ('${P.SON2}'), ('${P.SON3}');`);
await db.exec(lineage);

async function as(who, sql, params = []) {
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [JSON.stringify({ sub: who, role: 'authenticated' })]);
  await db.exec('set role authenticated');
  try { return { ok: true, rows: (await db.query(sql, params)).rows }; }
  catch (e) { return { ok: false, err: e.message, hint: e.hint }; }
  finally { await db.exec('reset role'); }
}
const one = async (sql, p = []) => (await db.query(sql, p)).rows[0];
const cnt = async (who, table) => { const r = await as(who, `select count(*)::int n from public.${table}`); return r.ok ? r.rows[0].n : r.err; };
const seen = async who => [await cnt(who, 'diwaniyas'), await cnt(who, 'projects'), await cnt(who, 'family_archive'),
  (await cnt(who, 'women_members')) > 0 ? 1 : 0].join(',');
const approveJoin = (who, m) => as(who, `select public.approve_join_as_daughter_son($1) as r`, [m]);
const decide = (who, rid, d, reason = null) => as(who, `select public.decide_lineage_request($1, $2, $3) as r`, [rid, d, reason]);
const submitNew = (who, a) => as(who, `select public.submit_daughter_son_lineage(
    p_mother_id => $1, p_father_id => $2, p_father_full_name => $3, p_father_deceased => $4,
    p_new_mother_name => $5, p_new_mother_father_id => $6, p_new_mother_deceased => $7) as id`,
  [a.mother ?? null, a.father ?? null, a.line ?? null, a.dead ?? false, a.newName ?? null, a.newFather ?? null, a.newDead ?? false]);
const searchD = (who, q) => as(who, `select public.search_daughters_for_lineage($1) as r`, [q]);
const searchM = (who, q) => as(who, `select public.search_men_for_lineage($1) as r`, [q]);

await approveJoin(P.O, P.SON);
check('قبل الترحيل: ابن البنت يرى كل الأقسام', await seen(P.SON) === '1,1,1,1', await seen(P.SON));

await db.exec(fix);
console.log('\n══════ بعد الإضافة ══════');
check('الإعدادات الثلاثة الجديدة', (await one(`select count(*)::int n from app_config where key in
  ('daughter_sons_locked_sections','daughter_sons_mother_min_parts','daughter_sons_father_min_words')`)).n === 3);
check('«نسبك» ← «أكمل حسابك» في عناوين الإعدادات',
  (await one(`select count(*)::int n from app_config where key like 'daughter_sons%' and (label_ar like '%نسبك%' or help_ar like '%نسبك%' or help_ar like '%نسبه%')`)).n === 0);

// ── القفل ──
check('ابن البنت (يحتاج): الديوانيات والمشاريع والمكتبة وشجرة النساء مقفولة', await seen(P.SON) === '0,0,0,0', await seen(P.SON));
check('العضو العادي لا يتأثر', await seen(P.M) === '1,1,1,1', await seen(P.M));
check('المالك لا يتأثر', await seen(P.O) === '1,1,1,1');
check('lineage_locked للعضو العادي = false', (await as(P.M, `select public.lineage_locked('diwaniyas') v`)).rows[0].v === false);
check('lineage_locked لقسم خارج القائمة = false', (await as(P.SON, `select public.lineage_locked('news') v`)).rows[0].v === false);
await db.exec(`update app_config set value = '["projects"]' where key = 'daughter_sons_locked_sections'`);
check('القائمة من الإعدادات: المشاريع فقط', await seen(P.SON) === '1,0,1,1', await seen(P.SON));
await db.exec(`update app_config set value = '[]' where key = 'daughter_sons_locked_sections'`);
check('[] = لا قفل', await seen(P.SON) === '1,1,1,1');
await db.exec(`delete from app_config where key = 'daughter_sons_locked_sections'`);
check('المفتاح غائب = الافتراضي (كلها مقفولة)', await seen(P.SON) === '0,0,0,0');
await db.exec(`insert into app_config (key, value, default_value, kind, category, label_ar)
  values ('daughter_sons_locked_sections', '["diwaniyas","projects","library","women_tree","member_details"]',
          '["diwaniyas","projects","library","women_tree","member_details"]', 'json', 'tree', 'x')`);
let r = await as(P.SON, `select count(*)::int n from women_members where id = $1`, [P.D1]);
check('بالمعرّف أيضاً: لا يقرأ صفاً من شجرة النساء', r.ok && r.rows[0].n === 0);

// ── البحث بلا تصفّح ──
r = await searchD(P.M, 'نورة عبدالله محمد');
check('البحث لغير ابن البنت مرفوض', !r.ok && r.hint === 'not_allowed', r.hint);
r = await searchD(P.SON, 'نورة عبدالله');
check('اسمان فقط → لا شيء (الاسم الثلاثي)', r.ok && r.rows[0].r.length === 0, JSON.stringify(r.rows?.[0]?.r));
r = await searchD(P.SON, 'نوره عبد الله محم');
let hits = r.rows?.[0]?.r ?? [];
check('ثلاثي (ة/ه، «عبد الله»، آخر كلمة ناقصة) → نورة وحدها', r.ok && hits.length === 1 && hits[0].id === P.D1, JSON.stringify(hits));
check('النتيجة: اسم أبيها وبلا زوج', hits[0]?.father_name === 'عبدالله محمد المحمدعلي' && hits[0]?.husband_id === null);
r = await searchD(P.SON, 'عبدالله محمد المحمدعلي');
check('السلسلة من الاسم الأول فقط (لا بنات بأسماء آبائهن)', r.ok && r.rows[0].r.length === 0);
r = await searchD(P.SON, 'نوف عبدالله محمد');
check('المخفية لا تظهر', r.ok && r.rows[0].r.length === 0);
await db.exec(`update app_config set value = '2' where key = 'daughter_sons_mother_min_parts'`);
r = await searchD(P.SON, 'هيا عبدالله');
check('الحد من الإعدادات (٢)', r.ok && r.rows[0].r.length === 1 && r.rows[0].r[0].id === P.D2);
await db.exec(`update app_config set value = '3' where key = 'daughter_sons_mother_min_parts'`);
r = await searchM(P.SON, 'سعود محمد');
check('رجال الشجرة: اسمان → لا شيء', r.ok && r.rows[0].r.length === 0);
r = await searchM(P.SON, 'سعود محمد المحمد');
hits = r.rows?.[0]?.r ?? [];
check('رجال الشجرة: ثلاثي → سعود (لا المعلّق)', r.ok && hits.length === 1 && hits[0].id === P.G, JSON.stringify(hits));

// ── الإرسال: «اسم الأب الكامل» سطراً واحداً ──
r = await submitNew(P.SON, { mother: P.D1, line: 'فهد ناصر' });
check('اسم الأب كلمتان → مرفوض', !r.ok && r.hint === 'name_required', r.hint);
await db.exec(`update app_config set value = 'true' where key = 'daughter_sons_require_grandfather'`);
r = await submitNew(P.SON, { mother: P.D1, line: 'فهد ناصر العتيبي' });
check('«اسم الجد إلزامي» القديم = ٤ كلمات', !r.ok && r.hint === 'name_required', r.hint);
await db.exec(`update app_config set value = 'false' where key = 'daughter_sons_require_grandfather'`);
r = await submitNew(P.SON, { mother: P.D1, line: '  فهد   ناصر  سعد العتيبي ', dead: true });
let rid = r.rows?.[0]?.id;
check('ثلاثي فأكثر → الطلب', r.ok && !!rid, r.err);
let det = JSON.parse((await one(`select details from admin_requests where id = $1`, [rid])).details);
check('التفاصيل: الأب سطر واحد + متوفى', det.father_name === 'فهد ناصر سعد العتيبي' && det.father.first_name === 'فهد'
  && det.father_is_deceased === true && det.v === 2, JSON.stringify(det));
check('قيد المراجعة: ما زال مقفولاً', await seen(P.SON) === '0,0,0,0');
r = await decide(P.MON, rid, 'reject', 'الاسم غلط');
let n = await one(`select title, body from notifications where target_member_id = $1 order by created_at desc limit 1`, [P.SON]);
check('الرفض: «راجع بياناتك وأرسلها من جديد» + السبب', r.ok && n.title === 'راجع بياناتك وأرسلها من جديد' && /أكمل حسابك/.test(n.body)
  && /الاسم غلط/.test(n.body), JSON.stringify(n));
// الحقول الأربعة القديمة (النسخ القديمة)
r = await as(P.SON, `select public.submit_daughter_son_lineage($1, null, 'فهد', 'ناصر', 'سعد', 'العتيبي', false) as id`, [P.D1]);
rid = r.rows?.[0]?.id;
check('النسخ القديمة: الحقول الأربعة ما زالت تعمل', r.ok && !!rid, r.err);
det = rid && JSON.parse((await one(`select details from admin_requests where id = $1`, [rid])).details);
check('القديمة: نفس الاسم الكامل والحقول محفوظة', det?.father_name === 'فهد ناصر سعد العتيبي' && det?.father?.family_name === 'العتيبي');
await db.exec(`update app_config set value = '{"notify_completed_title": "تم — حسابك مكتمل"}' where key = 'daughter_sons_texts'`);
r = await decide(P.O, rid, 'approve');
n = await one(`select title from notifications where target_member_id = $1 order by created_at desc limit 1`, [P.SON]);
check('القبول: عنوان الإشعار من daughter_sons_texts', r.ok && n.title === 'تم — حسابك مكتمل', r.err ?? n.title);
await db.exec(`update app_config set value = '{}' where key = 'daughter_sons_texts'`);
check('اكتمل: القفل انفكّ', await seen(P.SON) === '1,1,1,1', await seen(P.SON));
r = await searchD(P.SON, 'نورة عبدالله محمد');
check('بعد الاكتمال: البحث مرفوض', !r.ok && r.hint === 'not_allowed');

// ── «ما لقيت أمي؟» ──
await approveJoin(P.O, P.SON2);
n = await one(`select body from notifications where target_member_id = $1 and kind = 'join_approved'`, [P.SON2]);
check('إشعار قبول الانضمام بصيغة «أكمل حسابك»', /أكمل حسابك/.test(n.body) && !/نسبك/.test(n.body), n.body);
r = await submitNew(P.SON2, { newName: 'منيرة', newFather: P.PEND, line: 'خالد سعد العتيبي' });
check('أبوها غير موجود في الشجرة (معلّق) → مرفوض', !r.ok && r.hint === 'mother_father_not_found', r.hint);
r = await submitNew(P.SON2, { newName: 'منيرة', newFather: id(999), line: 'خالد سعد العتيبي' });
check('أبوها غير موجود أصلاً → مرفوض', !r.ok && r.hint === 'mother_father_not_found', r.hint);
r = await submitNew(P.SON2, { newName: 'منيرة', newFather: P.G, father: P.D1, line: '' });
check('أم جديدة مع زوج مسجّل → مرفوض', !r.ok && r.hint === 'bad_father', r.hint);
r = await submitNew(P.SON2, { newName: '  منيرة  سعود ', newFather: P.G, newDead: true, line: 'خالد سعد العتيبي' });
rid = r.rows?.[0]?.id;
check('«ما لقيت أمي؟»: الطلب', r.ok && !!rid, r.err);
det = rid && JSON.parse((await one(`select details from admin_requests where id = $1`, [rid])).details);
check('التفاصيل: «أم جديدة» + أبوها + متوفاة', det?.mother_id === null && det?.new_mother?.father_id === P.G
  && det?.new_mother?.first_name === 'منيرة' && det?.new_mother?.is_deceased === true, JSON.stringify(det));
check('G بلا عقدة في شجرة النساء قبل القرار', (await one(`select count(*)::int n from women_members where id = $1`, [P.G])).n === 0);
r = await decide(P.O, rid, 'approve');
let res = r.rows?.[0]?.r;
const gNode = await one(`select * from women_members where id = $1`, [P.G]);
const mom = res && await one(`select * from women_members where id = $1`, [res.mother_id]);
const hus = res && await one(`select * from women_members where id = $1`, [res.husband_id]);
const sn = res && await one(`select * from women_members where id = $1`, [res.son_node_id]);
check('القبول: عقدة أبيها أُنشئت بنفس معرّف شجرة الرجال', r.ok && gNode?.gender === 'male' && gNode?.full_name === 'سعود محمد المحمدعلي', r.err);
check('الأم: بنت سعود، متوفاة، اسمها + سلسلة أبيها', mom?.parent_id === P.G && mom?.gender === 'female' && mom?.is_deceased
  && mom?.full_name === 'منيرة سعود محمد المحمدعلي' && mom?.husband_id === res?.husband_id, JSON.stringify(mom));
check('الزوج من خارج العائلة تحتها', hus?.is_outside_family && hus?.full_name === 'خالد سعد العتيبي');
check('الابن: تحت الزوج، أمّه الجديدة، مربوط بحسابه', sn?.parent_id === hus?.id && sn?.mother_id === mom?.id && sn?.linked_user_id === P.SON2);
check('اكتمل ابن البنت الثاني', (await one(`select completed_at from daughter_son_lineage where profile_id = $1`, [P.SON2])).completed_at !== null);

// اسم مكرر لأم جديدة → مسموح (الإدارة تقرّر)
await approveJoin(P.O, P.SON3);
r = await submitNew(P.SON3, { newName: 'نورة', newFather: P.F, line: 'سعد ناصر العتيبي' });
rid = r.rows?.[0]?.id;
check('أم جديدة باسم بنت موجودة (نورة بنت عبدالله) → مسموح', r.ok && !!rid, r.err);
// حمولة معبوثة: أبوها ليس في شجرة الرجال → bad_payload
await db.exec(`update admin_requests set details = jsonb_set(details::jsonb, '{new_mother,father_id}', to_jsonb('${id(998)}'::text))::text where id = '${rid}'`);
r = await decide(P.O, rid, 'approve');
check('القرار: أبوها ليس في شجرة الرجال → bad_payload', !r.ok && r.hint === 'bad_payload', r.hint);
check('لا شيء أُنشئ بعد الفشل', (await one(`select count(*)::int n from women_members where linked_user_id = $1`, [P.SON3])).n === 0);
await db.exec(`update admin_requests set details = jsonb_set(details::jsonb, '{new_mother,father_id}', to_jsonb('${P.F}'::text))::text where id = '${rid}'`);
const d1Husband = (await one(`select husband_id from women_members where id = $1`, [P.D1])).husband_id;
r = await decide(P.O, rid, 'approve');
res = r.rows?.[0]?.r;
check('القرار بالأب الصحيح: نورة ثانية تحت عبدالله (لا مساس بالأولى)', r.ok && res.mother_id !== P.D1
  && (await one(`select count(*)::int n from women_members where parent_id = $1 and first_name = 'نورة'`, [P.F])).n === 2, r.err);
check('نورة الأولى وزوجها كما هما', (await one(`select husband_id from women_members where id = $1`, [P.D1])).husband_id === d1Husband);

await db.exec(undo);
console.log('\n══════ بعد التراجع ══════');
await db.exec(`insert into profiles(id, first_name, full_name, gender, role, status) values ('${id(30)}', 'وليد', 'وليد العتيبي', 'male', 'pending', 'pending');
  insert into admin_requests(member_id, requester_id, request_type, status) values ('${id(30)}', '${id(30)}', 'join_request', 'pending');
  insert into auth.users(id) values ('${id(30)}');`);
await approveJoin(P.O, id(30));
check('السياسات حُذفت: ابن بنت جديد يرى كل شي', await seen(id(30)) === '1,1,1,1', await seen(id(30)));
check('البحث حُذف', !(await searchD(id(30), 'نورة عبدالله محمد')).ok);
r = await as(id(30), `select public.submit_daughter_son_lineage($1, null, 'فهد', 'ناصر', '', 'العتيبي', false) as id`, [P.D2]);
check('الإرسال القديم رجع', r.ok, r.err);
check('الإعدادات الجديدة حُذفت', (await one(`select count(*)::int n from app_config where key in
  ('daughter_sons_locked_sections','daughter_sons_mother_min_parts','daughter_sons_father_min_words')`)).n === 0);
check('العناوين رجعت «نسبك»', (await one(`select label_ar from app_config where key = 'daughter_sons_allow_later'`)).label_ar.includes('«نسبك»'));
n = await one(`select body from notifications where kind = 'join_approved' and target_member_id = $1`, [id(30)]);
check('إشعار القبول رجع نصّه القديم', /نسبك/.test(n.body), n.body);

console.log(`\n${pass} نجح · ${fail} فشل`);
process.exit(fail ? 1 : 0);
