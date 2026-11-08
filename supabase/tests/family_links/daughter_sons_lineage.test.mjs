// تجربة 20261107120000_daughter_sons_lineage على قاعدة محلية معزولة (لا تلمس السيرفر):
//   «أبناء البنات من خارج العائلة» — قبول الانضمام كابن بنت، «نسبك» (الأم + الأب)، قرار الإدارة، زوج من خارج العائلة،
//   الإعدادات من app_config، ثم التراجع.
// التشغيل: cd supabase/tests/family_links && node daughter_sons_lineage.test.mjs
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
const fix = readFileSync(`${REPO}/migrations/20261107120000_daughter_sons_lineage.sql`, 'utf8');
const undo = readFileSync(`${REPO}/rollback/20261107120000_daughter_sons_lineage_rollback.sql`, 'utf8');

// ما يعتمد عليه الترحيل كما في السيرفر الحي (٢٠٢٦-١١-٠٧): الحارس (نصّه الحي حرفياً في الأجزاء التي يستبدلها الترحيل)،
// أسماء الأنواع، دور المختص، الإعدادات.
const live = `
alter table public.admin_requests add column details text, add column new_value text,
  add column created_at timestamptz default now(), add column admin_reply text, add column replied_at timestamptz,
  add column replied_by uuid references public.profiles(id);
alter table public.women_members add column wife_order integer;
create table public.app_config (key text primary key, value jsonb, default_value jsonb, kind text, category text,
  label_ar text, help_ar text, is_public boolean default false, sort int, min_value numeric, max_value numeric,
  max_length int, rules jsonb, updated_at timestamptz default now(), updated_by uuid);
create or replace function public.config_bool(p_key text, p_fallback boolean) returns boolean language sql stable
  security definer set search_path to '' as $$
  select coalesce((select case when jsonb_typeof(c.value) = 'boolean' then (c.value #>> '{}')::boolean end
                     from public.app_config c where c.key = p_key), p_fallback); $$;
create or replace function public.config_int(p_key text, p_fallback integer) returns integer language sql stable
  security definer set search_path to '' as $$
  select coalesce((select case when jsonb_typeof(c.value) = 'number' then (c.value #>> '{}')::numeric::integer end
                     from public.app_config c where c.key = p_key), p_fallback); $$;
create or replace function public.is_approved_member() returns boolean language sql stable security definer
  set search_path to 'public' as $$
  select coalesce(public.current_user_role() = any(array['member','supervisor','monitor','admin','owner']), false); $$;
create or replace function public.workflow_specialist_role(p_type text) returns text language sql immutable
  set search_path to 'public' as $function$
  select case when p_type in ('news_report', 'content_report') then 'supervisor'
    when p_type = 'contact_message' then null else 'monitor' end;
$function$;
create or replace function public.admin_request_label(p_type text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case p_type
    when 'join_request'     then 'طلب الانضمام'
    when 'relative_add'     then 'طلب إضافة قريبة'
    when 'account_delete'   then 'طلب حذف الحساب'
    else 'الطلب'
  end;
$function$;
create or replace function public.guard_admin_request_insert()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  me          uuid := auth.uid();
  my_profile  uuid := public.current_profile_id();
  caller_role text;
begin
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
       'phone_change','child_add','news_report','content_report','account_delete','privacy_request','relative_add') then
    raise exception 'admin_request_type_not_allowed' using errcode = '42501';
  end if;
  if new.request_type = 'relative_add' and coalesce(current_setting('app.self_relative_rpc', true), '') <> 'on' then
    raise exception 'admin_request_type_not_allowed' using errcode = '42501';
  end if;
  if new.requester_id is null
     or (new.requester_id is distinct from me and new.requester_id is distinct from my_profile) then
    raise exception 'admin_request_requester_not_self' using errcode = '42501';
  end if;
  return new;
end;
$function$;
create trigger trg_guard_admin_request_insert before insert on public.admin_requests
  for each row execute function public.guard_admin_request_insert();
alter table public.admin_requests enable row level security;
create policy ar_insert on public.admin_requests for insert with check (auth.uid() is not null and
  (requester_id = auth.uid() or public.current_user_role() = any (array['supervisor','admin','owner','monitor'])));
create policy ar_select on public.admin_requests for select using (requester_id = auth.uid() or member_id = auth.uid()
  or public.current_user_role() = any (array['supervisor','monitor','admin','owner']));
grant usage on schema auth to authenticated, anon;
grant select, insert, update, delete on public.admin_requests to authenticated;
grant select on public.women_members, public.profiles, public.notifications to authenticated;`;

const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
// O مالك · MON مراقب · S مشرف · M عضو · F أب في الشجرة · D1/D2 بنتاه بلا زوج · D3 بنته وزوجها من العائلة (H3 = ملف)
// SON ابن بنت بطلب انضمام · SON2 آخر لزوج مسجّل · W أنثى بطلب
const P = { O: id(1), MON: id(2), S: id(3), M: id(4), F: id(5), D1: id(10), D2: id(11), D3: id(12), H3: id(13),
  SON: id(20), SON2: id(21), W: id(22) };
let pass = 0, fail = 0;
const check = (l, ok, x = '') => { ok ? pass++ : fail++; console.log(`${ok ? '✅' : '❌'} ${l}${x ? ' — ' + x : ''}`); };

const db = new PGlite();
await db.exec(baseBody); await db.exec(preFns); await db.exec(baseTriggers); await db.exec(live);
await db.exec(`
  insert into profiles(id, first_name, full_name, gender, role, status) values
    ('${P.O}', 'مالك', 'المالك', 'male', 'owner', 'active'),
    ('${P.MON}', 'مراقب', 'المراقب', 'male', 'monitor', 'active'),
    ('${P.S}', 'مشرف', 'المشرف', 'male', 'supervisor', 'active'),
    ('${P.M}', 'عضو', 'عضو', 'male', 'member', 'active'),
    ('${P.F}', 'عبدالله', 'عبدالله المحمدعلي', 'male', 'member', 'active'),
    ('${P.H3}', 'حسن', 'حسن المحمدعلي', 'male', 'member', 'active'),
    ('${P.SON}', 'سالم', 'سالم فهد العتيبي', 'male', 'pending', 'pending'),
    ('${P.SON2}', 'ماجد', 'ماجد العتيبي', 'male', 'pending', 'pending'),
    ('${P.W}', 'ريم', 'ريم', 'female', 'pending', 'pending');
  insert into women_members(id, first_name, full_name, gender) values
    ('${P.F}', 'عبدالله', 'عبدالله المحمدعلي', 'male'), ('${P.H3}', 'حسن', 'حسن المحمدعلي', 'male')
    on conflict do nothing;
  insert into women_members(id, first_name, full_name, parent_id, gender, husband_id) values
    ('${P.D1}', 'نورة', 'نورة عبدالله المحمدعلي', '${P.F}', 'female', null),
    ('${P.D2}', 'هيا', 'هيا عبدالله المحمدعلي', '${P.F}', 'female', null),
    ('${P.D3}', 'سارة', 'سارة عبدالله المحمدعلي', '${P.F}', 'female', '${P.H3}');
  insert into admin_requests(member_id, requester_id, request_type, status) values
    ('${P.SON}', '${P.SON}', 'join_request', 'pending'), ('${P.SON2}', '${P.SON2}', 'join_request', 'pending'),
    ('${P.W}', '${P.W}', 'join_request', 'pending');
  insert into auth.users(id) values ('${P.O}'), ('${P.MON}'), ('${P.S}'), ('${P.M}'), ('${P.SON}'), ('${P.SON2}');`);

async function as(who, sql, params = []) {
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [JSON.stringify({ sub: who, role: 'authenticated' })]);
  await db.exec('set role authenticated');
  try { return { ok: true, rows: (await db.query(sql, params)).rows }; }
  catch (e) { return { ok: false, err: e.message, hint: e.hint }; }
  finally { await db.exec('reset role'); }
}
const one = async (sql, p = []) => (await db.query(sql, p)).rows[0];
const approveJoin = (who, m) => as(who, `select public.approve_join_as_daughter_son($1) as r`, [m]);
const submit = (who, mother, father, n1, n2, n3, n4, dec = false) =>
  as(who, `select public.submit_daughter_son_lineage($1, $2, $3, $4, $5, $6, $7) as id`, [mother, father, n1, n2, n3, n4, dec]);
const decide = (who, rid, d, reason = null) => as(who, `select public.decide_lineage_request($1, $2, $3) as r`, [rid, d, reason]);
const status = async (who) => (await as(who, `select public.my_lineage_status() as s`)).rows?.[0]?.s;

console.log('\n══════ قبل الإضافة ══════');
check('الدالة غير موجودة', !(await approveJoin(P.O, P.SON)).ok);

await db.exec(fix);
console.log('\n══════ بعد الإضافة ══════');
check('الإعدادات الخمسة في app_config', (await one(`select count(*)::int n from app_config where key like 'daughter_sons%'`)).n === 5);

let r = await approveJoin(P.S, P.SON);
check('المشرف لا يقبل', !r.ok && r.hint === 'not_allowed', r.hint);
r = await approveJoin(P.M, P.SON);
check('العضو لا يقبل', !r.ok && r.hint === 'not_allowed', r.hint);
r = await approveJoin(P.O, P.W);
check('طلب أنثى مرفوض (مكانها «ربط بشجرة النساء»)', !r.ok && r.hint === 'not_male', r.hint);
await db.exec(`update app_config set value = 'false' where key = 'daughter_sons_enabled'`);
r = await approveJoin(P.O, P.SON);
check('المفتاح مطفأ → مرفوض', !r.ok && r.hint === 'feature_off', r.hint);
await db.exec(`update app_config set value = 'true' where key = 'daughter_sons_enabled'`);

r = await approveJoin(P.MON, P.SON);
const son = await one(`select * from profiles where id = $1`, [P.SON]);
check('المراقب يقبل: عضو مفعّل مخفي من شجرة الرجال', r.ok && son.role === 'member' && son.status === 'active' && son.is_hidden_from_tree,
  r.err ?? `${son.role}/${son.status}`);
check('طلب الانضمام أُغلق «مقبول»',
  (await one(`select status from admin_requests where member_id = $1 and request_type = 'join_request'`, [P.SON])).status === 'approved');
r = await approveJoin(P.O, P.SON);
check('قبول ثانٍ مرفوض', !r.ok && r.hint === 'already_handled', r.hint);

let s = await status(P.SON);
check('«نسبك» مطلوب', s?.needs === true && s?.pending === false, JSON.stringify(s));
check('العضو العادي لا يحتاجه', (await status(P.M))?.needs === false);

r = await as(P.SON, `insert into admin_requests(member_id, requester_id, request_type, status) values ($1, $1, 'lineage_request', 'pending')`, [P.SON]);
check('إدراج «طلب النسب» مباشرة مرفوض من الحارس', !r.ok && /type_not_allowed/.test(r.err), r.err);
r = await as(P.SON, `update daughter_son_lineage set completed_at = now() where profile_id = $1`, [P.SON]);
check('العضو لا يعدّل علمه بنفسه', !r.ok, r.err ?? 'ALLOWED');
r = await submit(P.SON, P.F, null, 'فهد', 'ناصر', '', 'العتيبي');
check('الأم ليست بنتاً → مرفوض', !r.ok && r.hint === 'bad_mother', r.hint);
r = await submit(P.SON, P.D1, P.H3, null, null, null, null);
check('أب ليس زوج الأم → مرفوض', !r.ok && r.hint === 'bad_father', r.hint);
r = await submit(P.SON, P.D3, null, 'فهد', 'ناصر', '', 'العتيبي');
check('للأم زوج مسجّل و«أبوي مو موجود» → مرفوض', !r.ok && r.hint === 'mother_has_husband', r.hint);
r = await submit(P.SON, P.D3, P.H3, null, null, null, null);
check('زوجها من العائلة → «ربط بالشجرة»', !r.ok && r.hint === 'father_in_family', r.hint);
r = await submit(P.SON, P.D1, null, 'فهد', '', '', 'العتيبي');
check('اسم أبي الأب ناقص → مرفوض', !r.ok && r.hint === 'name_required', r.hint);
await db.exec(`update app_config set value = 'true' where key = 'daughter_sons_require_grandfather'`);
r = await submit(P.SON, P.D1, null, 'فهد', 'ناصر', '', 'العتيبي');
check('اسم الجد إلزامي من الإعدادات', !r.ok && r.hint === 'name_required', r.hint);
await db.exec(`update app_config set value = 'false' where key = 'daughter_sons_require_grandfather'`);

r = await submit(P.SON, P.D1, null, 'فهد', 'ناصر', 'سعد', 'العتيبي');
let rid = r.rows?.[0]?.id;
check('الإرسال ينشئ «طلب النسب»', r.ok && !!rid, r.err);
const req = await one(`select * from admin_requests where id = $1`, [rid]);
const det = JSON.parse(req.details);
check('التفاصيل: الأم + الأب الرباعي', det.mother_id === P.D1 && det.father_name === 'فهد ناصر سعد العتيبي', det.father_name);
check('وصل إشعار للإدارة (المالك والمراقب)',
  (await one(`select count(*)::int n from notifications where title = 'طلب نسب جديد'`)).n === 2);
r = await submit(P.SON, P.D1, null, 'فهد', 'ناصر', 'سعد', 'العتيبي');
check('إرسال ثانٍ وهو معلّق مرفوض', !r.ok && r.hint === 'already_pending', r.hint);
s = await status(P.SON);
check('الحالة: بانتظار الإدارة', s?.needs === false && s?.pending === true);

r = await decide(P.SON, rid, 'approve');
check('العضو لا يقرّر', !r.ok && r.hint === 'not_allowed', r.hint);
r = await decide(P.S, rid, 'approve');
check('المشرف لا يقرّر', !r.ok && r.hint === 'not_allowed', r.hint);
r = await decide(P.MON, rid, 'reject', 'اسم الجد غلط');
s = await status(P.SON);
check('الرفض: يرجع «نسبك» مع السبب', r.ok && s?.needs && s?.was_rejected && s?.rejected_reason === 'اسم الجد غلط', JSON.stringify(s));
check('لا عقد بعد الرفض', (await one(`select count(*)::int n from women_members where is_outside_family`)).n === 0);

await db.exec(`update app_config set value = '1' where key = 'daughter_sons_max_resubmits'`);
r = await submit(P.SON, P.D1, null, 'فهد', 'ناصر', 'سعد', 'العتيبي', true);
rid = r.rows?.[0]?.id;
check('إعادة الإرسال الأولى مسموحة', r.ok, r.err);
await decide(P.O, rid, 'reject');
r = await submit(P.SON, P.D1, null, 'فهد', 'ناصر', 'سعد', 'العتيبي', true);
check('حدّ إعادة الإرسال من الإعدادات', !r.ok && r.hint === 'resubmit_limit', r.hint);
await db.exec(`update app_config set value = '0' where key = 'daughter_sons_max_resubmits'`);
r = await submit(P.SON, P.D1, null, 'فهد', 'ناصر', 'سعد', 'العتيبي', true);
rid = r.rows?.[0]?.id;
check('٠ = بلا حد', r.ok, r.err);

r = await decide(P.O, rid, 'approve');
const res = r.rows?.[0]?.r;
const h = res && await one(`select * from women_members where id = $1`, [res.husband_id]);
const d1 = await one(`select * from women_members where id = $1`, [P.D1]);
const sn = res && await one(`select * from women_members where id = $1`, [res.son_node_id]);
check('القبول: زوج من خارج العائلة (ذكر، بلا أب، متوفى كما اختار)',
  r.ok && h.is_outside_family && h.gender === 'male' && h.parent_id === null && h.is_deceased && h.full_name === 'فهد ناصر سعد العتيبي',
  r.err ?? JSON.stringify(h));
check('الأم: husband_id = الزوج، متزوجة', d1.husband_id === res?.husband_id && d1.is_married === true);
check('الابن: تحت الزوج، أمّه البنت، مربوط بحسابه، بمعرّف جديد',
  sn && sn.parent_id === h.id && sn.mother_id === P.D1 && sn.linked_user_id === P.SON && sn.id !== P.SON
  && sn.full_name === 'سالم فهد ناصر سعد العتيبي', JSON.stringify(sn));
s = await status(P.SON);
check('النسب مكتمل', s?.completed === true && s?.needs === false);
r = await decide(P.O, rid, 'approve');
check('قرار ثانٍ مرفوض', !r.ok && r.hint === 'already_handled', r.hint);
await db.exec(`update profiles set full_name = 'سالم فهد ناصر العتيبي' where id = '${P.SON}'`);
check('تعديل اسم الحساب لا يحذف عقدته (المزامنة)',
  (await one(`select count(*)::int n from women_members where linked_user_id = $1`, [P.SON])).n === 1);
r = await as(P.O, `delete from women_members where id = $1`, [h.id]);
check('حذف الزوج وله ابن مرفوض (حماية الروابط)', !r.ok || (await one(`select count(*)::int n from women_members where id = $1`, [h.id])).n === 1);

// ابن ثانٍ يختار الزوج المسجّل
await approveJoin(P.O, P.SON2);
r = await submit(P.SON2, P.D1, h.id, null, null, null, null);
const rid2 = r.rows?.[0]?.id;
check('ابن ثانٍ يختار زوج أمّه المسجّل', r.ok, r.err);
r = await decide(P.O, rid2, 'approve');
check('القبول لا يُنشئ زوجاً ثانياً', r.ok && r.rows[0].r.husband_id === h.id
  && (await one(`select count(*)::int n from women_members where is_outside_family`)).n === 1, r.err);

// «زوج من خارج العائلة» من شجرة النساء
r = await as(P.M, `select public.add_outside_husband($1, $2, $3) as id`, [P.D2, 'خالد الفلاني', false]);
check('العضو لا يضيف زوجاً', !r.ok && r.hint === 'not_allowed', r.hint);
r = await as(P.MON, `select public.add_outside_husband($1, $2, $3) as id`, [P.D2, '  خالد   عبدالله الفلاني ', true]);
const h2 = r.ok && await one(`select * from women_members where id = $1`, [r.rows[0].id]);
check('المراقب يضيف زوجاً من خارج العائلة', r.ok && h2.is_outside_family && h2.first_name === 'خالد' && h2.full_name === 'خالد عبدالله الفلاني'
  && h2.is_deceased && (await one(`select husband_id from women_members where id = $1`, [P.D2])).husband_id === h2.id, r.err);
r = await as(P.O, `select public.add_outside_husband($1, $2, $3) as id`, [P.D2, 'ثاني', false]);
check('لها زوج → مرفوض (لا فكّ رابط)', !r.ok && r.hint === 'has_husband', r.hint);
r = await as(P.O, `select public.add_outside_husband($1, $2, $3) as id`, [P.F, 'س', false]);
check('ليست أنثى → مرفوض', !r.ok && r.hint === 'not_female_node', r.hint);

await db.exec(undo);
console.log('\n══════ بعد التراجع ══════');
check('الدوال حُذفت', !(await approveJoin(P.O, P.SON2)).ok);
check('العقد باقية', (await one(`select count(*)::int n from women_members where linked_user_id in ($1, $2)`, [P.SON, P.SON2])).n === 2);
r = await as(P.SON, `insert into admin_requests(member_id, requester_id, request_type, status) values ($1, $1, 'lineage_request', 'pending')`, [P.SON]);
check('الحارس رجع كما كان (النوع غير مقبول)', !r.ok && /type_not_allowed/.test(r.err), r.err);

console.log(`\n${pass} نجح · ${fail} فشل`);
process.exit(fail ? 1 : 0);
