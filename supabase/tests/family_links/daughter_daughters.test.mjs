// تجربة 20261127150000_daughter_daughters على قاعدة محلية معزولة (لا تلمس السيرفر):
//   «بنت بنت العائلة» — تسجّل ولم تجد أباها ← تختار أمّها من بنات العائلة وتكتب اسم أبيها ← الإدارة توافق:
//   أب من خارج العائلة زوجاً للأم (أو زوجها المسجّل إن تطابق الاسم)، عقدتها بمعرّف ملفها، تفعيل وإشعار.
//   وفرع الابن: عقدته بمعرّف ملفه. والمزامنة لا تحذف عقدة صاحب الحساب. ثم التراجع.
// التشغيل: cd supabase/tests/family_links && node daughter_daughters.test.mjs
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
const fix = mig('20261127150000_daughter_daughters');
const undo = readFileSync(`${REPO}/rollback/20261127150000_daughter_daughters_rollback.sql`, 'utf8');
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
// O مالك · MON مراقب · S مشرف · M عضو · F رجل من العائلة · H3 زوج من العائلة
// D1 بنت F بلا زوج · D2 بنت F زوجها H2 من خارج العائلة «حسن حسين علي الموسى» · D3 بنت F زوجها H3 من العائلة
// DD1..DD5 مسجّلات معلّقات · MP رجل معلّق · SON ابن بنت
const P = { O: id(1), MON: id(2), S: id(3), M: id(4), F: id(5), H3: id(6), D1: id(10), D2: id(11), D3: id(12), H2: id(13),
  DD1: id(20), DD2: id(21), DD3: id(22), DD4: id(23), DD5: id(24), MP: id(25), SON: id(30) };
let pass = 0, fail = 0;
const check = (l, ok, x = '') => { ok ? pass++ : fail++; console.log(`${ok ? '✅' : '❌'} ${l}${x ? ' — ' + x : ''}`); };

const db = new PGlite();
await db.exec(baseBody); await db.exec(preFns); await db.exec(baseTriggers); await db.exec(live); await db.exec(sections);
await db.exec(mig('20261107120000_daughter_sons_lineage'));
await db.exec(mig('20261108090000_daughter_sons_restricted'));
await db.exec(liveGuard);
await db.exec(mig('20261126090000_outside_family_women'));
await db.exec(mig('20261126170000_outside_family_men'));
await db.exec(`
  insert into profiles(id, first_name, full_name, gender, role, status) values
    ('${P.O}', 'مالك', 'المالك', 'male', 'owner', 'active'),
    ('${P.MON}', 'مراقب', 'المراقب', 'male', 'monitor', 'active'),
    ('${P.S}', 'مشرف', 'المشرف', 'male', 'supervisor', 'active'),
    ('${P.M}', 'عضو', 'عضو', 'male', 'member', 'active'),
    ('${P.F}', 'حسين', 'حسين علي المحمدعلي', 'male', 'member', 'active'),
    ('${P.H3}', 'جاسم', 'جاسم محمد المحمدعلي', 'male', 'member', 'active'),
    ('${P.DD1}', 'أسماء', 'أسماء الموسى', 'female', 'pending', 'pending'),
    ('${P.DD2}', 'مريم', 'مريم الموسى', 'female', 'pending', 'pending'),
    ('${P.DD3}', 'سارة', 'سارة الرشيد', 'female', 'pending', 'pending'),
    ('${P.DD4}', 'هند', 'هند المحمدعلي', 'female', 'pending', 'pending'),
    ('${P.DD5}', 'لولوة', 'لولوة الكندري', 'female', 'pending', 'pending'),
    ('${P.MP}', 'خالد', 'خالد العتيبي', 'male', 'pending', 'pending'),
    ('${P.SON}', 'سالم', 'سالم العتيبي', 'male', 'pending', 'pending');
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
    ('${P.DD1}', '${P.DD1}', 'link_request', 'pending', 'طلب انضمام جديد — لا توجد مطابقات بالاسم في الشجرة'),
    ('${P.DD2}', '${P.DD2}', 'join_request', 'pending', null),
    ('${P.DD3}', '${P.DD3}', 'join_request', 'pending', null),
    ('${P.DD4}', '${P.DD4}', 'link_request', 'pending', 'طلب انضمام جديد|father_id:${P.F}|father_name:حسين'),
    ('${P.DD5}', '${P.DD5}', 'join_request', 'pending', null),
    ('${P.MP}', '${P.MP}', 'join_request', 'pending', null),
    ('${P.SON}', '${P.SON}', 'join_request', 'pending', null);
  insert into auth.users(id) select id from profiles;
  grant select on public.app_config to authenticated;`);

async function as(who, sql, params = []) {
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [JSON.stringify({ sub: who, role: 'authenticated' })]);
  await db.exec('set role authenticated');
  try { return { ok: true, rows: (await db.query(sql, params)).rows }; }
  catch (e) { return { ok: false, err: e.message, hint: e.hint }; }
  finally { await db.exec('reset role'); }
}
const sys = async sql => { await db.query(`select set_config('request.jwt.claims', '', false)`); await db.exec(sql); };
const one = async (sql, p = []) => (await db.query(sql, p)).rows[0];
const submit = (who, a) => as(who, `select public.submit_daughter_daughter_lineage(
    p_mother_id => $1, p_father_full_name => $2, p_father_deceased => $3, p_father_id => $4) as id`,
  [a.mother ?? null, a.line ?? null, a.dead ?? false, a.father ?? null]);
const decide = (who, rid, d, reason = null) => as(who, `select public.decide_lineage_request($1, $2, $3) as r`, [rid, d, reason]);
const status = async who => (await as(who, `select public.my_daughter_lineage_status() as s`)).rows?.[0]?.s;
const searchD = (who, q) => as(who, `select public.search_daughters_for_lineage($1) as r`, [q]);
const node = nid => one(`select * from women_members where id = $1`, [nid]);

console.log('\n══════ قبل الإضافة ══════');
check('الدالة غير موجودة', !(await submit(P.DD1, { mother: P.D1, line: 'حسن حسين الموسى' })).ok);
let r = await searchD(P.DD1, 'نورة حسين علي');
check('البحث للمعلّقة مرفوض قبله', !r.ok && r.hint === 'not_allowed', r.hint);

await db.exec(fix);
console.log('\n══════ بعد الإضافة ══════');
check('الإعداد daughter_daughters_enabled', (await one(`select value from app_config where key = 'daughter_daughters_enabled'`))?.value === true);

// ── من تحق لها ──
let s = await status(P.DD1);
check('المسجّلة بلا أب: eligible', s?.eligible === true && s?.pending === false, JSON.stringify(s));
check('اختارت أباها عند التسجيل: لا', (await status(P.DD4))?.eligible === false);
check('رجل معلّق: لا', (await status(P.MP))?.eligible === false);
check('عضو مفعّل: لا', (await status(P.M))?.eligible === false);
r = await searchD(P.DD1, 'نوره حسين علي');
let hits = r.rows?.[0]?.r ?? [];
check('بحث الأم للمسجّلة (ة/ه، الثلاثي)', r.ok && hits.length === 1 && hits[0].id === P.D1, JSON.stringify(r.err ?? hits));
r = await searchD(P.DD1, 'نورة حسين');
check('اسمان فقط → لا شيء', r.ok && r.rows[0].r.length === 0);
check('من اختارت أباها لا تبحث', (await searchD(P.DD4, 'نورة حسين علي')).hint === 'not_allowed');
check('العضو العادي لا يبحث', (await searchD(P.M, 'نورة حسين علي')).hint === 'not_allowed');
r = await submit(P.DD4, { mother: P.D1, line: 'حسن حسين الموسى' });
check('من اختارت أباها لا ترسل', !r.ok && r.hint === 'not_allowed', r.hint);

// ── الحارس ──
r = await as(P.DD1, `insert into admin_requests(member_id, requester_id, request_type, status, details)
  values ($1, $1, 'lineage_request', 'pending', '{"kind":"daughter_daughter"}')`, [P.DD1]);
check('الحارس: طلب نسب مباشر بلا الدالة مرفوض', !r.ok && /admin_request_type_not_allowed/.test(r.err), r.err);
r = await as(P.DD1, `insert into admin_requests(member_id, requester_id, request_type, status, details)
  values ($1, $1, 'name_change', 'pending', 'x')`, [P.DD1]);
check('الحارس: المعلّقة لا ترسل غير الانضمام والتواصل (كما كان)', !r.ok && /requires_active_member/.test(r.err), r.err);

// ── الإرسال: حالات الرفض ──
r = await submit(P.DD1, { mother: P.F, line: 'حسن حسين الموسى' });
check('الأم ليست بنتاً → bad_mother', !r.ok && r.hint === 'bad_mother', r.hint);
r = await submit(P.DD1, { mother: P.D1, line: 'حسن الموسى' });
check('اسم أب بكلمتين → name_required', !r.ok && r.hint === 'name_required', r.hint);
r = await submit(P.DD5, { mother: P.D3, line: 'جاسم محمد المحمدعلي' });
check('زوج الأم من العائلة → father_in_family', !r.ok && r.hint === 'father_in_family', r.hint);
r = await submit(P.DD2, { mother: P.D1, father: P.H2 });
check('أب مسجّل ليس زوج الأم → bad_father', !r.ok && r.hint === 'bad_father', r.hint);

// ── ١) أمّها بلا زوج: أب جديد من خارج العائلة ──
r = await submit(P.DD1, { mother: P.D1, line: 'حسن  حسين الموسى', dead: true });
let rid1 = r.rows?.[0]?.id;
check('أسماء ترسل: أمّها نورة وأبوها مكتوب', r.ok && !!rid1, r.err);
let d = JSON.parse((await one(`select details from admin_requests where id = $1`, [rid1])).details);
check('الحمولة: kind = daughter_daughter، الاسم مطبّع', d.kind === 'daughter_daughter' && d.father_name === 'حسن حسين الموسى' && d.mother_id === P.D1);
check('الإدارة يصلها «طلب نسب جديد»', (await one(`select count(*)::int n from notifications where title = 'طلب نسب جديد' and created_by = $1`, [P.DD1])).n === 2);
check('حالتها: pending', (await status(P.DD1))?.pending === true);
r = await submit(P.DD1, { mother: P.D1, line: 'حسن حسين الموسى' });
check('مرة ثانية وهو معلّق → already_pending', !r.ok && r.hint === 'already_pending', r.hint);

// صلاحيات القرار
check('المشرف لا يقرّر', (await decide(P.S, rid1, 'approve')).hint === 'not_allowed');
check('العضو لا يقرّر', (await decide(P.M, rid1, 'approve')).hint === 'not_allowed');
check('صاحبة الطلب لا تقرّر', (await decide(P.DD1, rid1, 'approve')).hint === 'not_allowed');

r = await decide(P.MON, rid1, 'approve');
let res = r.rows?.[0]?.r;
check('المراقب يوافق', r.ok && res?.kind === 'daughter_daughter', r.err);
let her = await node(P.DD1);
let dad = await node(res?.husband_id);
check('١) أبوها: ذكر من خارج العائلة بلا أب، متوفى كما كتبت', dad?.gender === 'male' && dad?.is_outside_family === true
  && dad?.parent_id === null && dad?.full_name === 'حسن حسين الموسى' && dad?.is_deceased === true, JSON.stringify(dad));
check('١) زوجاً لأمّها', (await node(P.D1)).husband_id === dad?.id);
check('٢) عقدتها id = معرّف ملفها و linked_user_id = ملفها', her?.id === P.DD1 && her?.linked_user_id === P.DD1);
check('٢) أبوها parent_id وأمّها mother_id، أنثى', her?.parent_id === dad?.id && her?.mother_id === P.D1 && her?.gender === 'female');
check('٢) is_outside_family يحسبه السيرفر = true', her?.is_outside_family === true);
check('٢) الاسم: أسماء + اسم أبيها', her?.full_name === 'أسماء حسن حسين الموسى', her?.full_name);
let pr = await one(`select role, status, is_hidden_from_tree from profiles where id = $1`, [P.DD1]);
check('٣) الملف: عضو مفعّل مخفي من شجرة الرجال', pr.role === 'member' && pr.status === 'active' && pr.is_hidden_from_tree === true);
let reqs = (await db.query(`select request_type, status, replied_by, replied_at from admin_requests where member_id = $1 order by request_type`, [P.DD1])).rows;
check('٣) طلب النسب وطلب الربط مقبولان بمن ومتى', reqs.length === 2 && reqs.every(x => x.status === 'approved' && x.replied_by === P.MON && x.replied_at));
let n = await one(`select * from notifications where target_member_id = $1 and kind = 'join_approved'`, [P.DD1]);
check('٣) إشعار join_approved بالنص', n?.title === 'مرحباً بك في العائلة' && n?.body === 'تم قبول طلب انضمامك وربطك بشجرة النساء');
check('لا صفّ ابن بنت لها', (await one(`select count(*)::int n from daughter_son_lineage where profile_id = $1`, [P.DD1])).n === 0);
check('الموافقة مرة ثانية → already_handled', (await decide(P.O, rid1, 'approve')).hint === 'already_handled');
check('بعد القبول لم تعد eligible', (await status(P.DD1))?.eligible === false);

// ── المزامنة لا تحذف عقدتها ──
await sys(`update profiles set full_name = 'أسماء حسن الموسى', is_hidden_from_tree = false where id = '${P.DD1}'`);
her = await node(P.DD1);
check('تعديل اسم الملف وإخفائه: العقدة باقية باسمها وظاهرة', !!her && her.full_name === 'أسماء حسن حسين الموسى' && her.is_hidden_from_tree === false, JSON.stringify(her));
await sys(`update profiles set is_deceased = true where id = '${P.DD1}'`);
check('الوفاة تُنقل لعقدتها', (await node(P.DD1))?.is_deceased === true);
await sys(`update profiles set is_deceased = false where id = '${P.DD1}'`);
await sys(`insert into profiles(id, first_name, full_name, gender, role, status) values ('${id(40)}', 'ماجد', 'ماجد', 'male', 'member', 'active');
  insert into women_members(id, first_name, full_name, gender) values ('${id(40)}', 'ماجد', 'ماجد', 'male');
  update profiles set full_name = 'ماجد ناصر' where id = '${id(40)}';`);
check('مرآة يتيمة بلا حساب مربوط تُحذف (كما كانت)', !(await node(id(40))));

// ── ٢) أمّها لها زوج من خارج العائلة والاسم يطابقه ← يُعاد ──
r = await submit(P.DD2, { mother: P.D2, line: 'حسن حسين الموسى' });
let rid2 = r.rows?.[0]?.id;
d = JSON.parse((await one(`select details from admin_requests where id = $1`, [rid2])).details);
check('مريم ترسل باسم مختصر لزوج أمّها: بلا تعارض', r.ok && d.husband_conflict === false && d.mother_husband_id === P.H2, r.err);
const husbandsBefore = (await one(`select count(*)::int n from women_members where gender = 'male' and is_outside_family`)).n;
r = await decide(P.O, rid2, 'approve');
res = r.rows?.[0]?.r;
check('الموافقة تعيد زوج الأم المسجّل', r.ok && res?.husband_id === P.H2 && res?.husband_reused === true, r.err);
check('لا زوج جديد', (await one(`select count(*)::int n from women_members where gender = 'male' and is_outside_family`)).n === husbandsBefore);
her = await node(P.DD2);
check('عقدتها تحت H2 وأمّها فاطمة، والاسم بالاسم المسجّل', her?.id === P.DD2 && her?.parent_id === P.H2 && her?.mother_id === P.D2
  && her?.full_name === 'مريم حسن حسين علي الموسى', her?.full_name);
check('زوج فاطمة كما هو', (await node(P.D2)).husband_id === P.H2);

// ── ٣) أمّها لها زوج آخر ← يُرفض (لا كتابة فوقه) ──
r = await submit(P.DD3, { mother: P.D2, line: 'سالم أحمد الرشيد' });
let rid3 = r.rows?.[0]?.id;
d = JSON.parse((await one(`select details from admin_requests where id = $1`, [rid3])).details);
check('سارة ترسل اسماً غير زوج أمّها: husband_conflict', r.ok && d.husband_conflict === true, r.err);
r = await decide(P.O, rid3, 'approve');
check('الموافقة ترفض: mother_has_other_husband', !r.ok && r.hint === 'mother_has_other_husband', r.hint);
check('لا شيء تغيّر: زوج فاطمة H2 ولا عقدة لسارة', (await node(P.D2)).husband_id === P.H2 && !(await node(P.DD3)));
check('طلب سارة ما زال معلّقاً', (await one(`select status from admin_requests where id = $1`, [rid3])).status === 'pending');
r = await decide(P.O, rid3, 'reject', 'أبوك ليس زوج أمك المسجّل');
check('الرفض', r.ok, r.err);
n = await one(`select * from notifications where target_member_id = $1 and kind = 'request_rejected'`, [P.DD3]);
check('إشعار الرفض مؤنّث مع السبب', /راجعي/.test(n?.title ?? '') && /السبب: أبوك/.test(n?.body ?? ''), n?.body);
check('طلب انضمامها باقٍ معلّقاً', (await one(`select status from admin_requests where member_id = $1 and request_type = 'join_request'`, [P.DD3])).status === 'pending');
s = await status(P.DD3);
check('حالتها: eligible + was_rejected + السبب', s?.eligible && s?.was_rejected && s?.rejected_reason === 'أبوك ليس زوج أمك المسجّل', JSON.stringify(s));
r = await submit(P.DD3, { mother: P.D1, line: 'سالم أحمد الرشيد' });
check('ترسل من جديد بعد الرفض', r.ok, r.err);
// نورة صار لها زوج (أبو أسماء) — اسم مختلف → تعارض
d = JSON.parse((await one(`select details from admin_requests where id = $1`, [r.rows?.[0]?.id])).details);
check('نورة صار لها زوج: اسم مختلف = تعارض', d.husband_conflict === true);

// زوجها المسجّل اختيار مباشر (p_father_id)
r = await submit(P.DD5, { mother: P.D2, father: P.H2 });
check('اختيار زوج الأم المسجّل مباشرة', r.ok, r.err);
r = await decide(P.O, r.rows?.[0]?.id, 'approve');
check('الموافقة: تحت H2', r.ok && (await node(P.DD5))?.parent_id === P.H2, r.err);

// المفتاح
await sys(`update app_config set value = 'false' where key = 'daughter_daughters_enabled'`);
await sys(`insert into profiles(id, first_name, full_name, gender, role, status) values ('${id(41)}', 'دانة', 'دانة', 'female', 'pending', 'pending'); insert into auth.users(id) values ('${id(41)}');`);
r = await submit(id(41), { mother: P.D1, line: 'سالم أحمد الرشيد' });
check('المفتاح مطفأ → feature_off', !r.ok && r.hint === 'feature_off', r.hint);
check('المفتاح مطفأ: eligible = false', (await status(id(41)))?.eligible === false);
await sys(`update app_config set value = 'true' where key = 'daughter_daughters_enabled'`);

// ── الابن: عقدته الآن بمعرّف ملفه ──
r = await as(P.O, `select public.approve_join_as_daughter_son($1) as r`, [P.SON]);
check('قبول ابن البنت', r.ok, r.err);
r = await as(P.SON, `select public.submit_daughter_son_lineage(p_mother_id => $1, p_father_full_name => $2) as id`, [P.D3, 'ناصر فهد العتيبي']);
check('الابن: أمّ زوجها من العائلة مرفوضة (كما كان)', !r.ok && r.hint === 'mother_has_husband', r.hint);
await sys(`insert into women_members(id, first_name, full_name, parent_id, gender) values ('${id(14)}', 'هيا', 'هيا حسين علي المحمدعلي', '${P.F}', 'female')`);
r = await as(P.SON, `select public.submit_daughter_son_lineage(p_mother_id => $1, p_father_full_name => $2) as id`, [id(14), 'ناصر فهد العتيبي']);
check('الابن يرسل', r.ok, r.err);
r = await decide(P.O, r.rows?.[0]?.id, 'approve');
res = r.rows?.[0]?.r;
let sonNode = await node(P.SON);
check('الابن: son_node_id = معرّف ملفه', r.ok && res?.son_node_id === P.SON && sonNode?.linked_user_id === P.SON, r.err);
check('الابن: تحت الأب الجديد وأمّه هيا', sonNode?.parent_id === res?.husband_id && sonNode?.mother_id === id(14));
check('صفّ ابن البنت: women_node_id = ملفه، مكتمل', (await one(`select women_node_id, completed_at from daughter_son_lineage where profile_id = $1`, [P.SON])).women_node_id === P.SON);
await sys(`update profiles set full_name = 'سالم ناصر العتيبي' where id = '${P.SON}'`);
check('الابن: تعديل اسم ملفه لا يحذف عقدته', !!(await node(P.SON)));

await db.exec(undo);
console.log('\n══════ بعد التراجع ══════');
check('الدوال الجديدة حُذفت', (await one(`select count(*)::int n from pg_proc where proname in ('submit_daughter_daughter_lineage','my_daughter_lineage_status','lineage_daughter_applicant','lineage_search_caller','lineage_names_match')`)).n === 0);
check('الإعداد حُذف', (await one(`select count(*)::int n from app_config where key = 'daughter_daughters_enabled'`)).n === 0);
check('الحارس رجع', !(await one(`select pg_get_functiondef('public.guard_admin_request_insert()'::regprocedure) d`)).d.includes('20261127150000'));
check('المزامنة رجعت', !(await one(`select pg_get_functiondef('public.sync_profile_update_to_women()'::regprocedure) d`)).d.includes('linked_user_id'));
check('القرار رجع (بلا فرع البنت)', !(await one(`select pg_get_functiondef('public.decide_lineage_request(uuid,text,text)'::regprocedure) d`)).d.includes('daughter_daughter'));
r = await searchD(P.DD3, 'نورة حسين علي');
check('البحث رجع لابن البنت وحده', !r.ok && r.hint === 'not_allowed', r.hint);
check('العُقد الموجودة باقية', !!(await node(P.DD1)) && !!(await node(P.DD2)) && !!(await node(P.SON)));

console.log(`\n${pass} نجح · ${fail} فشل`);
process.exit(fail ? 1 : 0);
