// تجربة 20261127160000_outside_family_signup على قاعدة محلية معزولة (لا تلمس السيرفر):
//   «من خارج العائلة»: التسجيل بعلامة ← الإدارة تقبل الانضمام (approve_join_as_daughter_son — الذكر والأنثى الآن) ←
//   «استكمال التسجيل»: «هل الأم من العائلة؟» نعم ← اسمها مكتوباً (outside_typed) والإدارة تختارها من المقترحات
//   (lineage_mother_suggestions) ثم decide_lineage_request(…, p_mother_id): عقدته بجنس ملفه، زوج الوالدة يُعاد إن طابق الوالد
//   المشتق من اسمه ولا كتابة فوق زوج مختلف · لا ← mark_outside_mother: «صلاحيات محدودة» دائمة بلا طلب ولا كتابة في الشجرة
//   (lineage_locked من outside_member_locked_sections).
//   والإشعار يصله أيّاً كان من قرّر. ثم التراجع.
// التشغيل: cd supabase/tests/family_links && node outside_family_signup.test.mjs
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
const mig = f => readFileSync(`${REPO}/migrations/${f}.sql`, 'utf8');
const dd = mig('20261127150000_daughter_daughters');
const fix = mig('20261127160000_outside_family_signup');
const undo = readFileSync(`${REPO}/rollback/20261127160000_outside_family_signup_rollback.sql`, 'utf8');
// ما قبله كما في الحي: الحارس الأساسي من تجربة 20261107120000، ثم الترحيلات بالترتيب
const prevTest = readFileSync(new URL('./daughter_sons_lineage.test.mjs', import.meta.url), 'utf8');
const live = prevTest.slice(prevTest.indexOf('const live = `') + 'const live = `'.length, prevTest.indexOf('`;', prevTest.indexOf('const live = `')));
// الحارس الحي (٢٠٢٦-١١-٢٧) في الأجزاء التي تخصّ الطلبات هنا — الشرط الذي يستبدله الترحيل حرفياً
const liveGuard = String.raw`CREATE OR REPLACE FUNCTION public.guard_admin_request_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me          uuid := auth.uid();
  my_profile  uuid := public.current_profile_id();
  caller_role text;
  d           jsonb;
  act         text;
  tgt         text;
  par         text;
  member_name text;
  child       record;
  uuid_re     constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
begin
  -- السيرفر وصيانة SQL (مثل حارس الأدوار prevent_role_self_promotion).
  if auth.role() = 'service_role'
     or (auth.role() is null and session_user in ('postgres','supabase_admin','supabase_auth_admin')) then
    return new;
  end if;
  -- بلا دخول: سياسات الجدول ترفضه.
  if me is null then
    return new;
  end if;
  caller_role := coalesce(public.current_user_role(), 'pending');
  if caller_role in ('owner','admin','monitor','supervisor') then
    return new;
  end if;

  new.status      := 'pending';
  new.admin_reply := null;
  new.replied_at  := null;
  new.replied_by  := null;
  new.created_at  := now();

  if new.request_type is null or new.request_type not in (
       'link_request','contact_message','tree_edit','name_change','family_change',
       'phone_change','child_add','news_report','content_report','account_delete','privacy_request','relative_add','lineage_request','relative_remove') then
    raise exception 'admin_request_type_not_allowed' using errcode = '42501';
  end if;
  -- «إضافة قريبة» تُنشئها add_self_wife/add_self_mother/add_or_link_self_relative فقط (20261029140000)
  if new.request_type = 'relative_add' and coalesce(current_setting('app.self_relative_rpc', true), '') <> 'on' then
    raise exception 'admin_request_type_not_allowed' using errcode = '42501';
  end if;
  -- «طلب حذف من الشجرة» تُنشئه remove_self_child/remove_self_wife/remove_self_woman_child فقط (20261113130000)
  if new.request_type = 'relative_remove' and coalesce(current_setting('app.self_remove_rpc', true), '') <> 'on' then
    raise exception 'admin_request_type_not_allowed' using errcode = '42501';
  end if;
  -- «طلب النسب» تُنشئه submit_daughter_son_lineage فقط (20261107120000)
  if new.request_type = 'lineage_request' and coalesce(current_setting('app.lineage_rpc', true), '') <> 'on' then
    raise exception 'admin_request_type_not_allowed' using errcode = '42501';
  end if;
  if new.requester_id is null
     or (new.requester_id is distinct from me and new.requester_id is distinct from my_profile) then
    raise exception 'admin_request_requester_not_self' using errcode = '42501';
  end if;
  if new.member_id is null then
    raise exception 'admin_request_member_required' using errcode = '42501';
  end if;
  if new.request_type not in ('link_request','contact_message','account_delete') and not public.is_approved_member() then
    raise exception 'admin_request_requires_active_member' using errcode = '42501';
  end if;
  if new.request_type <> 'tree_edit' and new.member_id <> new.requester_id then
    raise exception 'admin_request_not_about_self' using errcode = '42501';
  end if;

  -- (بقية الحارس الحي — tree_edit/child_add/content_report — لا تخصّ هذه التجربة؛ نصّها الحي كاملاً في 20261004200000 وما بعده)
  return new;
end;
$function$
;
`;
const sections = `
create schema if not exists private;
create table public.diwaniyas (id uuid primary key default gen_random_uuid(), name text);
create table public.projects (id uuid primary key default gen_random_uuid(), title text);
create table public.family_archive (id uuid primary key default gen_random_uuid(), title text);
grant usage on schema private to authenticated;`;

const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
// O مالك · A مدير · MON مراقب · M عضو · F رجل من العائلة · H3 زوج من العائلة · H2 زوج من خارج العائلة
// D1 بنت F بلا زوج · D2 بنت F زوجها H2 «حسن حسين علي الموسى» · D3 بنت F زوجها H3
// G1 بنت سجّلت «من خارج العائلة» · B1/B2/B3 أبناء سجّلوا «من خارج العائلة» · DD بنت بنت (قيد المراجعة، المسار الحي)
const P = { O: id(1), A: id(2), MON: id(3), M: id(4), F: id(5), H3: id(6), D1: id(10), D2: id(11), D3: id(12), H2: id(13),
  G1: id(20), B1: id(21), B2: id(22), B3: id(23), DD: id(24), X1: id(25), FS: id(26) };
let pass = 0, fail = 0;
const check = (l, ok, x = '') => { ok ? pass++ : fail++; console.log(`${ok ? '✅' : '❌'} ${l}${x ? ' — ' + x : ''}`); };
const informal = /أبوك|أباك|أبيك|أمّك|أمك/;

const db = new PGlite();
await db.exec(baseBody); await db.exec(preFns); await db.exec(baseTriggers); await db.exec(live); await db.exec(sections);
await db.exec(mig('20261107120000_daughter_sons_lineage'));
await db.exec(mig('20261108090000_daughter_sons_restricted'));
await db.exec(liveGuard);
await db.exec(mig('20261126090000_outside_family_women'));
await db.exec(mig('20261126170000_outside_family_men'));
await db.exec(dd);
const marker = 'طلب انضمام جديد — من خارج العائلة|outside_family:1';
await db.exec(`
  insert into profiles(id, first_name, full_name, gender, role, status) values
    ('${P.O}', 'مالك', 'المالك', 'male', 'owner', 'active'),
    ('${P.A}', 'مدير', 'المدير', 'male', 'admin', 'active'),
    ('${P.MON}', 'مراقب', 'المراقب', 'male', 'monitor', 'active'),
    ('${P.M}', 'عضو', 'عضو', 'male', 'member', 'active'),
    ('${P.F}', 'حسين', 'حسين علي المحمدعلي', 'male', 'member', 'active'),
    ('${P.H3}', 'جاسم', 'جاسم محمد المحمدعلي', 'male', 'member', 'active');
  insert into profiles(id, first_name, full_name, family_name, gender, role, status) values
    ('${P.G1}', 'سارة حسن حسين الموسى', 'سارة حسن حسين الموسى', 'الموسى', 'female', 'pending', 'pending'),
    ('${P.B1}', 'سالم ناصر فهد العتيبي', 'سالم ناصر فهد العتيبي', 'العتيبي', 'male', 'pending', 'pending'),
    ('${P.B2}', 'خالد جاسم محمد الرشيد', 'خالد جاسم محمد الرشيد', 'الرشيد', 'male', 'pending', 'pending'),
    ('${P.B3}', 'فهد سالم أحمد الكندري', 'فهد سالم أحمد الكندري', 'الكندري', 'male', 'pending', 'pending'),
    ('${P.DD}', 'لولوة', 'لولوة الكندري', null, 'female', 'pending', 'pending'),
    ('${P.X1}', 'ماجد', 'ماجد', null, 'male', 'pending', 'pending'),
    ('${P.FS}', 'هيا', 'هيا أحمد علي المحمدعلي', 'المحمدعلي', 'female', 'pending', 'pending');
  insert into women_members(id, first_name, full_name, gender) values
    ('${P.F}', 'حسين', 'حسين علي المحمدعلي', 'male'), ('${P.H3}', 'جاسم', 'جاسم محمد المحمدعلي', 'male')
    on conflict do nothing;
  insert into women_members(id, first_name, full_name, gender, is_outside_family) values
    ('${P.H2}', 'حسن', 'حسن حسين علي الموسى', 'male', true);
  insert into women_members(id, first_name, full_name, parent_id, gender, husband_id) values
    ('${P.D1}', 'نورة', 'نورة حسين علي المحمدعلي', '${P.F}', 'female', null),
    ('${P.D2}', 'فاطمة', 'فاطمة حسين علي المحمدعلي', '${P.F}', 'female', '${P.H2}'),
    ('${P.D3}', 'زينب', 'زينب حسين علي المحمدعلي', '${P.F}', 'female', '${P.H3}');
  insert into admin_requests(member_id, requester_id, request_type, status, details) values
    ('${P.G1}', '${P.G1}', 'link_request', 'pending', '${marker}'),
    ('${P.B1}', '${P.B1}', 'link_request', 'pending', '${marker}'),
    ('${P.B2}', '${P.B2}', 'link_request', 'pending', '${marker}'),
    ('${P.B3}', '${P.B3}', 'link_request', 'pending', '${marker}'),
    ('${P.DD}', '${P.DD}', 'join_request', 'pending', null),
    ('${P.X1}', '${P.X1}', 'link_request', 'pending', '${marker}'),
    ('${P.FS}', '${P.FS}', 'link_request', 'pending', 'طلب انضمام جديد — لا توجد مطابقات بالاسم في الشجرة|family_signup:1');
  insert into auth.users(id) select id from profiles;
  grant select on public.app_config to authenticated;`);

async function as(who, sql, params = []) {
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [JSON.stringify({ sub: who, role: 'authenticated' })]);
  await db.exec('set role authenticated');
  try { return { ok: true, rows: (await db.query(sql, params)).rows }; }
  catch (e) { return { ok: false, err: e.message, hint: e.hint }; }
  finally { await db.exec('reset role'); }
}
const one = async (sql, p = []) => (await db.query(sql, p)).rows[0];
const approveJoin = (who, member) => as(who, `select public.approve_join_as_daughter_son($1) as r`, [member]);
const submit = (who, name) => as(who, `select public.submit_outside_lineage(p_mother_name => $1) as id`, [name]);
const markLimited = who => as(who, `select public.mark_outside_mother() as r`);
const decide = (who, rid, d, reason = null) => as(who, `select public.decide_lineage_request($1, $2, $3) as r`, [rid, d, reason]);
const decideWith = (who, rid, mom) => as(who, `select public.decide_lineage_request($1, 'approve', null, $2) as r`, [rid, mom]);
const suggest = (who, rid) => as(who, `select public.lineage_mother_suggestions($1) as r`, [rid]);
const status = async who => (await as(who, `select public.my_lineage_status() as s`)).rows?.[0]?.s;
const node = nid => one(`select * from women_members where id = $1`, [nid]);
const details = async rid => JSON.parse((await one(`select details from admin_requests where id = $1`, [rid])).details);
const lastNote = (who, kind) => one(`select * from notifications where target_member_id = $1 and kind = $2 order by created_at desc, id desc limit 1`, [who, kind]);

const ddStatus = async who => (await as(who, `select public.my_daughter_lineage_status() as s`)).rows?.[0]?.s;
console.log('\n══════ قبل الترحيل (الحي) ══════');
check('بطاقة «بنت بنت» قبله: تظهر للمسجّلة «من العائلة» بلا والد', (await ddStatus(P.FS))?.eligible === true);
let r = await approveJoin(P.MON, P.G1);
check('قبول البنت «من خارج العائلة» مرفوض قبله: not_male', !r.ok && r.hint === 'not_male', r.hint);

await db.exec(fix);
console.log('\n══════ بعد الترحيل ══════');

check('بطاقة «بنت بنت» لا تظهر لمن سجّلت «من العائلة» الجديد (الإدارة تربطها)', (await ddStatus(P.FS))?.eligible === false);
check('ولا لمن سجّلت «من خارج العائلة» (استكمال التسجيل بعد القبول)', (await ddStatus(P.G1))?.eligible === false);
check('وتبقى لمن سجّلت قبل هذه الخطوة', (await ddStatus(P.DD))?.eligible === true);

// ── البنت: قبول الانضمام ──
r = await approveJoin(P.MON, P.G1);
check('المراقب يقبل البنت «من خارج العائلة»', r.ok, r.err);
let pr = await one(`select role, status, is_hidden_from_tree, family_name from profiles where id = $1`, [P.G1]);
check('حسابها مفعّل مخفي من شجرة الرجال، والعائلة محفوظة', pr.role === 'member' && pr.status === 'active' && pr.is_hidden_from_tree && pr.family_name === 'الموسى');
check('صفّها «بانتظار النسب»', !!(await one(`select 1 x from daughter_son_lineage where profile_id = $1 and completed_at is null`, [P.G1])));
let n = await lastNote(P.G1, 'join_approved');
check('إشعار القبول رسمي: «استكمال التسجيل»، بلا أبوك/أمك', /استكمال التسجيل/.test(n?.body ?? '') && !informal.test(n?.body ?? ''), n?.body);
let s = await status(P.G1);
check('حالتها: flagged + needs', s?.flagged && s?.needs && !s?.pending, JSON.stringify(s));

// ── «نعم»: اسم الوالدة مكتوباً، والوالد من اسمها ──
check('اسم الوالدة كلمة واحدة → name_required', (await submit(P.G1, 'فاطمة')).hint === 'name_required');
r = await submit(P.G1, '  فاطمه  حسين علي ');
let rid = r.rows?.[0]?.id;
check('«نعم» ترسل اسم الوالدة', r.ok && !!rid, r.err);
let d = await details(rid);
check('الحمولة: outside_typed، العائلة «المحمدعلي» ثابتة، الوالد من اسمها', d.kind === 'outside_typed' && d.mother_family === 'المحمدعلي'
  && d.mother_typed_name === 'فاطمه حسين علي' && d.father_name === 'حسن حسين الموسى' && d.mother_id === null, JSON.stringify(d));
check('حالتها: pending', (await status(P.G1))?.pending === true);
check('مرة ثانية → already_pending', (await submit(P.G1, 'فاطمة حسين علي')).hint === 'already_pending');
check('العضو لا يرى المقترحات', (await suggest(P.M, rid)).hint === 'not_allowed');
r = await suggest(P.MON, rid);
let sug = r.rows?.[0]?.r ?? [];
check('المقترحات للمراقب: فاطمة (ة/ه) وزوجها يطابق الوالد', r.ok && sug.length === 1 && sug[0].id === P.D2 && sug[0].husband_matches === true
  && sug[0].father_name === 'حسين علي المحمدعلي', JSON.stringify(r.err ?? sug));
r = await decide(P.MON, rid, 'approve');
check('الموافقة بلا اختيار الوالدة → mother_required', !r.ok && r.hint === 'mother_required', r.hint);
r = await decideWith(P.MON, rid, P.D2);
check('المراقب يختار فاطمة ويوافق', r.ok, r.err);
let her = await node(P.G1);
check('عقدتها: id = ملفها، أنثى، تحت H2 (زوج الوالدة المطابق) وأمّها فاطمة', her?.linked_user_id === P.G1 && her?.gender === 'female'
  && her?.parent_id === P.H2 && her?.mother_id === P.D2, JSON.stringify(her));
check('صفّها مكتمل (women_node_id = ملفها)', (await one(`select women_node_id from daughter_son_lineage where profile_id = $1 and completed_at is not null`, [P.G1]))?.women_node_id === P.G1);
n = await lastNote(P.G1, 'admin');
check('إشعار الاكتمال يصلها من المراقب، رسمي', n?.created_by === P.MON && /الوالدة فاطمة والوالد حسن حسين علي الموسى/.test(n?.body ?? '')
  && !informal.test(n?.body ?? ''), n?.body);
check('حالتها: completed', (await status(P.G1))?.completed === true);

// ── الابن: زوج الوالدة باسم آخر ثم والدة بلا زوج ──
check('المدير يقبل الابن', (await approveJoin(P.A, P.B1)).ok);
r = await submit(P.B1, 'فاطمة حسين');
rid = r.rows?.[0]?.id;
check('B1 يرسل (اسمان)', r.ok && (await details(rid)).father_name === 'ناصر فهد العتيبي', r.err);
sug = (await suggest(P.A, rid)).rows?.[0]?.r ?? [];
check('المقترحات بكلمتين: البنات اللاتي يبدأ اسمهن «فاطمة حسين»، وزوجها لا يطابق', sug.length === 1 && sug[0].husband_matches === false);
r = await decideWith(P.MON, rid, P.D2);
check('زوج الوالدة باسم آخر → mother_has_other_husband', !r.ok && r.hint === 'mother_has_other_husband', r.hint);
check('لا عقدة له ولا تغيّر زوج فاطمة', !(await node(P.B1)) && (await node(P.D2)).husband_id === P.H2);
r = await decide(P.MON, rid, 'reject', 'الوالدة غير صحيحة');
n = await lastNote(P.B1, 'request_rejected');
check('المراقب يرفض: الإشعار يصله، رسمي مع السبب', r.ok && n?.created_by === P.MON && /استكمال التسجيل/.test(n?.body ?? '')
  && /السبب: الوالدة غير صحيحة/.test(n?.body ?? '') && !informal.test(n?.title + n?.body), n?.body);
r = await submit(P.B1, 'نورة حسين علي');
check('B1 يرسل من جديد', r.ok, r.err);
r = await decideWith(P.A, r.rows?.[0]?.id, P.D1);
let dad = await node(r.rows?.[0]?.r?.husband_id);
check('المدير يوافق: والد جديد من خارج العائلة (من اسمه) زوجاً لنورة', r.ok && dad?.is_outside_family && dad?.full_name === 'ناصر فهد العتيبي'
  && (await node(P.D1)).husband_id === dad?.id, r.err ?? JSON.stringify(dad));
let son = await node(P.B1);
check('عقدته ذكر تحت والده وأمّه نورة', son?.gender === 'male' && son?.parent_id === dad?.id && son?.mother_id === P.D1);
check('إشعار الاكتمال يصله من المدير', (await lastNote(P.B1, 'admin'))?.created_by === P.A);

// ── زوج الوالدة من العائلة ──
check('المالك يقبل B2', (await approveJoin(P.O, P.B2)).ok);
r = await submit(P.B2, 'زينب حسين علي');
r = await decideWith(P.O, r.rows?.[0]?.id, P.D3);
check('زوج الوالدة من العائلة → father_in_family', !r.ok && r.hint === 'father_in_family', r.hint);
check('له طلب نسب معلّق: لا يختار «لا» → already_pending', (await markLimited(P.B2)).hint === 'already_pending');

// ── «هل الأم من العائلة؟» لا ← صلاحيات محدودة مباشرة، بلا طلب ──
check('المراقب يقبل B3', (await approveJoin(P.MON, P.B3)).ok);
check('عضو عادي (بلا صفّ نسب) لا يستعملها → not_needed', (await markLimited(P.M)).hint === 'not_needed');
check('غير المفعّل لا يستعملها → not_allowed', (await markLimited(P.DD)).hint === 'not_allowed');
const nodesBefore = (await one(`select count(*)::int n from women_members`)).n;
const reqsBefore = (await one(`select count(*)::int n from admin_requests`)).n;
r = await markLimited(P.B3);
check('«لا»: mark_outside_mother', r.ok && r.rows[0].r.limited === true, r.err);
check('لا طلب للإدارة ولا كتابة في الشجرة', (await one(`select count(*)::int n from admin_requests`)).n === reqsBefore
  && (await one(`select count(*)::int n from women_members`)).n === nodesBefore && !(await node(P.B3)));
check('مرة ثانية → not_needed', (await markLimited(P.B3)).hint === 'not_needed');
check('صفّه: صلاحيات محدودة (limited_at) لا اكتمال، بلا عقدة', !!(await one(`select 1 x from daughter_son_lineage
  where profile_id = $1 and limited_at is not null and completed_at is null and women_node_id is null`, [P.B3])));
s = await status(P.B3);
check('حالته: limited، بلا needs ولا completed (لا «استكمال التسجيل»)', s?.limited === true && s?.needs === false && s?.completed === false, JSON.stringify(s));
const locked = async (who, sec) => (await as(who, `select public.lineage_locked($1) as l`, [sec])).rows?.[0]?.l;
check('القفل الدائم: الديوانيات وشجرة النساء مقفولة عليه', await locked(P.B3, 'diwaniyas') === true && await locked(P.B3, 'women_tree') === true);
await db.query(`select set_config('request.jwt.claims', '', false)`);
// الحي: RLS مفعّل على شجرة النساء بقراءة للمسجّلين + سياسة القفل RESTRICTIVE (20261108090000) — نفس الشيء هنا
await db.exec(`alter table women_members enable row level security;
  create policy wm_read_test on women_members for select to authenticated using (true);`);
{ const w = await as(P.B3, `select count(*)::int n from women_members`); const g = await as(P.G1, `select count(*)::int n from women_members`);
  check('السيرفر يمنعه قراءة شجرة النساء (والمكتملة تقرؤها)', w.ok && w.rows[0].n === 0 && g.ok && g.rows[0].n > 0, JSON.stringify([w, g])); }
await db.exec(`drop policy wm_read_test on women_members; alter table women_members disable row level security;`);
check('من اكتمل تسجيلها لا قفل عليها', await locked(P.G1, 'diwaniyas') === false);
await db.query(`select set_config('request.jwt.claims', '', false)`);
await db.exec(`update app_config set value = '["library"]' where key = 'outside_member_locked_sections'`);
check('القائمة من السيرفر (outside_member_locked_sections): الديوانيات تُفتح والمكتبة تبقى',
  await locked(P.B3, 'diwaniyas') === false && await locked(P.B3, 'library') === true);
await db.exec(`update app_config set value = '["diwaniyas", "projects", "library", "women_tree", "member_details"]' where key = 'outside_member_locked_sections'`);
check('بعدها لا يرسل اسم الوالدة → not_needed', (await submit(P.B3, 'مريم سالم أحمد')).hint === 'not_needed');

// ── اسم الوالد غير مكتمل في الملف ──
check('المراقب يقبل X1', (await approveJoin(P.MON, P.X1)).ok);
check('اسم الحساب كلمة واحدة → father_name_missing', (await submit(P.X1, 'نورة حسين علي')).hint === 'father_name_missing');
check('«استكمال التسجيل» قبل الاعتماد: القفل المؤقت كما كان', await locked(P.X1, 'diwaniyas') === true);

// ── «بنت بنت» قيد المراجعة (الحي): الرفض بنص رسمي ──
r = await as(P.DD, `select public.submit_daughter_daughter_lineage(p_mother_id => $1, p_father_full_name => $2) as id`, [P.D2, 'سالم أحمد الرشيد']);
check('بنت بنت (قيد المراجعة) ترسل كما كانت', r.ok, r.err);
r = await decide(P.MON, r.rows?.[0]?.id, 'reject');
n = await lastNote(P.DD, 'request_rejected');
check('رفضها من المراقب بنص رسمي', r.ok && n?.created_by === P.MON && /الوالدة/.test(n?.body ?? '') && !informal.test(n?.title + n?.body), n?.body);
check('العضو لا يقبل انضماماً', (await approveJoin(P.M, P.DD)).hint === 'not_allowed');
check('القرار بثلاثة معاملات (النسخ القديمة) يعمل', (await decide(P.M, rid, 'approve')).hint === 'not_allowed');

await db.exec(undo);
console.log('\n══════ بعد التراجع ══════');
await db.query(`select set_config('request.jwt.claims', '', false)`);
await db.exec(`insert into profiles(id, first_name, full_name, gender, role, status) values ('${id(40)}', 'هند', 'هند', 'female', 'pending', 'pending');
  insert into admin_requests(member_id, requester_id, request_type, status, details) values ('${id(40)}', '${id(40)}', 'link_request', 'pending', '${marker}');
  insert into profiles(id, first_name, full_name, gender, role, status) values ('${id(41)}', 'ماجد', 'ماجد', 'male', 'pending', 'pending');
  insert into auth.users(id) values ('${id(40)}'), ('${id(41)}');`);
r = await approveJoin(P.MON, id(40));
check('قبول البنت رجع مرفوضاً: not_male', !r.ok && r.hint === 'not_male', r.hint);
check('المراقب يقبل ابناً', (await approveJoin(P.MON, id(41))).ok);
check('نص القبول القديم رجع', /أكمل حسابك/.test((await lastNote(id(41), 'join_approved'))?.body ?? ''));
check('الدوال الجديدة حُذفت', (await one(`select count(*)::int n from pg_proc where proname in ('submit_outside_lineage','lineage_mother_suggestions','mark_outside_mother')`)).n === 0);
const defs = (await db.query(`select pg_get_function_identity_arguments(oid) a, pg_get_functiondef(oid) d from pg_proc where proname = 'decide_lineage_request'`)).rows;
check('القرار رجع بثلاثة معاملات كما في 20261127150000', defs.length === 1 && !defs[0].a.includes('p_mother_id')
  && !defs[0].d.includes('استكمال التسجيل') && defs[0].d.includes('daughter_daughter'), JSON.stringify(defs.map(x => x.a)));
check('العُقد الموجودة باقية', !!(await node(P.G1)) && !!(await node(P.B1)));
check('العمود والإعداد حُذفا', !(await one(`select 1 x from information_schema.columns where table_name = 'daughter_son_lineage' and column_name = 'limited_at'`))
  && !(await one(`select 1 x from app_config where key = 'outside_member_locked_sections'`)));
check('حالة النسب رجعت بلا limited', (await status(P.B3))?.limited === undefined);
check('بطاقة «بنت بنت» رجعت كما كانت', (await ddStatus(P.FS))?.eligible === true);

console.log(`\n${pass} نجح · ${fail} فشل`);
process.exit(fail ? 1 : 0);
