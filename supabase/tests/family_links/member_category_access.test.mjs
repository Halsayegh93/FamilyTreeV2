// تجربة 20261127190000_member_category_access («صلاحيات الأعضاء حسب الفئة») على قاعدة محلية معزولة — لا تلمس السيرفر.
// app_config وفحصه وسجلّه وset_app_config وapp_config() منسوخة حرفياً من الحي عبر تجربة admin_role_matrix (نفس النص).
// يثبت: الفئة لكل نوع حساب، القيمة الأولى تطوي القائمة القديمة (لا يتغيّر شيء على أحد)، التعديل للمالك وحده، الفحص يرفض
// الفئة/المفتاح غير المعروف والقيمة غير المنطقية و«حسابي» ومفاتيح الإبلاغ والحظر، الأم المطفأة تخفي أبناءها،
// lineage_locked يقفل القراءة حسب الفئة (والقديم احتياط للمحدود، وحالة «استكمال التسجيل» كما هي)، members_masked يخفي الرقم
// حين يُطفأ «الهاتف والاتصال»، سياسات الإدراج، والتراجع يرجع الحي حرفياً.
// التشغيل: cd supabase/tests/family_links && node member_category_access.test.mjs
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
process.on('unhandledRejection', e => { console.log('خطأ:', e.message, (e.query ?? '').slice(0, 300)); process.exit(2); });

const REPO = fileURLToPath(new URL('../../', import.meta.url));
const MIG = readFileSync(`${REPO}/migrations/20261127190000_member_category_access.sql`, 'utf8');
const RB = readFileSync(`${REPO}/rollback/20261127190000_member_category_access_rollback.sql`, 'utf8');
// الفئة السابعة «لم يستكمل التسجيل» (20261127210000) — تُجرَّب فوق 20261127190000 ثم تُتراجع قبل تراجعه
const MIG2 = readFileSync(`${REPO}/migrations/20261127210000_member_category_incomplete.sql`, 'utf8');
const RB2 = readFileSync(`${REPO}/rollback/20261127210000_member_category_incomplete_rollback.sql`, 'utf8');
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
// نفس الأسماء التي تُدرجها كتلة الحي المنسوخة: المالك، المدير، المراقب، المشرف، عضو
const O = id(1), A = id(2), MON = id(3), S = id(4), M = id(5);
const W = id(6), DS = id(7), DD = id(8), LIM = id(9), OSW = id(10), OSH = id(11), PEND = id(12), DDN = id(13), FROZ = id(14);
// لم يستكمل: ابن بنت · بنت بنت أرسلت اسم الوالدة وتنتظر · حساب المراجعة في الحالة نفسها
const INC = id(15), INCF = id(16), REV = id(17);
let pass = 0, fail = 0;
const ok = (c, m, x = '') => { if (c) { pass++; console.log('✓', m); } else { fail++; console.log('✗', m, x); } };
const unmark = s => s.replaceAll('<BS>', '\\').replaceAll('<FFFF>', '￿').replaceAll('<BT>', '`');

const db = new PGlite();
await db.exec(`
do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if;
end $$;
create schema auth;
create schema private;
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
-- أول خمسة أعمدة كما تُدرجها كتلة الحي، ثم أعمدة members_masked
create table public.profiles (id uuid primary key, role text, status text, full_name text, first_name text,
  gender text, father_id uuid, mother_id uuid, husband_id uuid, phone_number text, is_phone_hidden boolean default false,
  birth_date date, death_date date, is_deceased boolean default false, photo_url text, is_hidden_from_tree boolean default false,
  sort_order int default 0, bio_json jsonb, sons_ids uuid[], created_at timestamptz default now(), is_married boolean,
  avatar_url text, bio text, is_approved boolean default true, is_admin boolean default false, is_phone_verified boolean,
  is_birth_date_hidden boolean default false, cover_url text, badge_enabled boolean, updated_by uuid, updated_at timestamptz,
  is_hr_member boolean, hr_status text, last_seen_at timestamptz, registration_platform text, username text,
  last_active_at timestamptz, current_screen text, current_screen_source text, email text, terms_accepted_at timestamptz,
  family_name text, death_date_unknown boolean, avatar_unavailable boolean, is_photo_hidden boolean default false,
  activity_visible boolean default true);
create function public.current_profile_id() returns uuid language sql stable as $$ select auth.uid() $$;
create function public.current_user_role() returns text language sql stable security definer set search_path to 'public' as $$
  select case when p.status = 'active' then p.role when p.status in ('frozen','deleted') then p.status else 'pending' end
  from public.profiles p where p.id = public.current_profile_id() $$;
create function public.is_team(uid uuid) returns boolean language sql stable security definer set search_path to 'public' as $$
  select coalesce(public.current_user_role() in ('owner','admin','monitor','supervisor'), false) $$;
create function public.is_approved_member() returns boolean language sql stable security definer set search_path to 'public' as $$
  select coalesce(public.current_user_role() in ('owner','admin','monitor','supervisor','member'), false) $$;
create table public.app_settings (id int primary key default 1, sms_wait_seconds int default 60,
  allow_new_registrations boolean default true, updated_at timestamptz default now());
insert into public.app_settings (id) values (1);
create table public.app_config (
  key text primary key check (key ~ '^[a-z][a-z0-9_]{1,62}$'),
  value jsonb not null, default_value jsonb not null,
  kind text not null check (kind = any (array['int', 'bool', 'text', 'text_long', 'json'])),
  min_value numeric, max_value numeric,
  max_length integer check (max_length is null or (max_length >= 1 and max_length <= 10000)),
  category text not null check (category = any (array['members', 'news', 'tree', 'notifications', 'approvals', 'deaths', 'sms', 'links', 'general'])),
  label_ar text not null check (btrim(label_ar) <> ''), help_ar text,
  rules jsonb not null default '{}'::jsonb check (jsonb_typeof(rules) = 'object'),
  is_public boolean not null default false, sort integer not null default 0,
  updated_at timestamptz not null default now(), updated_by uuid references public.profiles(id) on delete set null,
  check (min_value is null or max_value is null or min_value <= max_value));
create table public.app_config_history (id bigserial primary key, key text, old_value jsonb, new_value jsonb, changed_by uuid,
  changed_by_name text, changed_at timestamptz default now());
`);

// الحي حرفياً — كتلة تجربة admin_role_matrix (app_config_problem وفحصه وسجلّه وset_app_config وapp_config() والأدوار الخمسة)
const arm = readFileSync(new URL('./admin_role_matrix.test.mjs', import.meta.url), 'utf8');
const block = arm.slice(arm.indexOf('// ═══ الحي حرفياً'), arm.indexOf('const LIVE = {'));
await new (Object.getPrototypeOf(async function () {}).constructor)('db', 'unmark', 'O', 'A', 'MON', 'S', 'M', block)(db, unmark, O, A, MON, S, M);

await db.exec(`
-- الأعضاء: كل نوع حساب
update public.profiles set gender = 'male' where id in ('${O}', '${A}', '${MON}', '${S}', '${M}');
update public.profiles set phone_number = '+96550000005' where id = '${M}';
insert into public.profiles (id, role, status, full_name, first_name, gender, father_id, phone_number, is_phone_hidden) values
  ('${W}', 'member', 'active', 'نورة', 'نورة', 'female', null, '+96550000006', true),
  ('${DS}', 'member', 'active', 'ابن بنت', 'سالم', 'male', null, '+96550000007', false),
  ('${DD}', 'member', 'active', 'بنت بنت', 'هيا', 'female', null, null, true),
  ('${LIM}', 'member', 'active', 'محدود', 'فهد', 'male', null, null, false),
  ('${OSW}', 'member', 'active', 'زوجة من عائلة أخرى', 'منى', 'female', null, null, true),
  ('${OSH}', 'member', 'active', 'زوج بنت', 'خالد', 'male', null, null, false),
  ('${PEND}', 'pending', 'pending', 'معلّق', 'معلّق', 'male', null, null, false),
  ('${DDN}', 'member', 'active', 'بنت بنت بعقدتها', 'سارة', 'female', null, null, true),
  ('${FROZ}', 'member', 'frozen', 'موقوف', 'موقوف', 'male', null, null, false),
  ('${INC}', 'member', 'active', 'ابن بنت لم يستكمل', 'ناصر', 'male', null, null, false),
  ('${INCF}', 'member', 'active', 'بنت بنت تنتظر الإدارة', 'ريم', 'female', null, null, true),
  ('${REV}', 'member', 'active', 'حساب المراجعة', 'مراجعة', 'male', null, null, false);
update public.profiles set father_id = '${O}' where id = '${M}';

create table public.daughter_son_lineage (profile_id uuid primary key references public.profiles(id) on delete cascade,
  approved_by uuid, approved_at timestamptz default now(), women_node_id uuid, completed_at timestamptz, limited_at timestamptz);
insert into public.daughter_son_lineage (profile_id, completed_at, limited_at) values
  ('${DS}', now(), null), ('${DD}', now(), null), ('${LIM}', null, now()), ('${S}', null, now()),
  ('${INC}', null, null), ('${INCF}', null, null), ('${REV}', null, null);
-- «حساب المراجعة» (الحي: app_config.review_account_ids) — بديل صغير في القاعدة المعزولة
create table public.test_review_ids(id uuid);
insert into public.test_review_ids values ('${REV}');
create function public.review_account_ids() returns uuid[] language sql stable as
  $f$ select coalesce(array_agg(id), '{}'::uuid[]) from public.test_review_ids $f$;
create table public.women_members (id uuid primary key default gen_random_uuid(), full_name text, gender text default 'female',
  parent_id uuid references public.women_members(id), mother_id uuid references public.women_members(id),
  husband_id uuid, linked_user_id uuid, is_outside_family boolean not null default false);
insert into public.women_members (id, full_name, gender, parent_id, mother_id, linked_user_id, is_outside_family) values
  ('${id(100)}', 'بنت العائلة (الأم)', 'female', null, null, null, false),
  ('${id(101)}', 'زوجها من خارج العائلة', 'male', null, null, null, true),
  ('${DDN}', 'سارة', 'female', '${id(101)}', '${id(100)}', '${DDN}', true),
  ('${id(102)}', 'منى', 'female', null, null, '${OSW}', true),
  ('${id(103)}', 'خالد', 'male', null, null, '${OSH}', true),
  ('${id(104)}', 'نورة', 'female', null, null, '${W}', false);

insert into public.app_config (key, value, default_value, kind, category, label_ar, sort) values
  ('outside_member_locked_sections', '["diwaniyas", "projects", "library", "women_tree", "member_details"]',
   '["diwaniyas", "projects", "library", "women_tree", "member_details"]', 'json', 'tree', 'الأقسام المقفولة', 75),
  ('daughter_sons_locked_sections', '["diwaniyas", "projects", "library", "women_tree", "member_details"]',
   '["diwaniyas", "projects", "library", "women_tree", "member_details"]', 'json', 'tree', 'أقسام ابن البنت', 74);

-- الجداول التي يحرسها الترحيل، بسياساتها الحالية (مفتوحة للمسجّل + القفل المقيّد من 20261108090000)
create table public.news (id uuid primary key default gen_random_uuid(), author_id uuid, content text);
create table public.news_comments (id uuid primary key default gen_random_uuid(), news_id uuid, author_id uuid, content text);
create table public.news_likes (news_id uuid, member_id uuid);
create table public.news_poll_votes (news_id uuid, member_id uuid, option_index int);
create table public.diwaniyas (id uuid primary key default gen_random_uuid(), title text);
create table public.projects (id uuid primary key default gen_random_uuid(), title text);
create table public.family_archive (id uuid primary key default gen_random_uuid(), title text);
do $$ declare t text; begin
  foreach t in array array['news','news_comments','news_likes','news_poll_votes','diwaniyas','projects','family_archive','women_members'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I on public.%I for all to authenticated using (true) with check (true)', t || '_open', t);
    execute format('grant select, insert on public.%I to authenticated', t);
  end loop;
end $$;
insert into public.diwaniyas (title) values ('ديوانية'); insert into public.projects (title) values ('مشروع');
insert into public.family_archive (title) values ('كتاب');
grant select on public.profiles, public.daughter_son_lineage to authenticated;
`);
// lineage_locked وسياساته كما في الحي (20261127160000 + 20261108090000)
const OFS = readFileSync(`${REPO}/migrations/20261127160000_outside_family_signup.sql`, 'utf8');
const ll = OFS.slice(OFS.indexOf('create or replace function public.lineage_locked(p_section text)'),
                     OFS.indexOf("Used by RESTRICTIVE select policies.';", OFS.indexOf('create or replace function public.lineage_locked')) + 38);
await db.exec(ll + `
grant execute on function public.lineage_locked(text) to authenticated;
create policy diwaniyas_lineage_locked on public.diwaniyas as restrictive for select to authenticated
  using (not (select public.lineage_locked('diwaniyas')));
create policy projects_lineage_locked on public.projects as restrictive for select to authenticated
  using (not (select public.lineage_locked('projects')));
create policy family_archive_lineage_locked on public.family_archive as restrictive for select to authenticated
  using (not (select public.lineage_locked('library')));
create policy women_members_lineage_locked on public.women_members as restrictive for select to authenticated
  using (not (select public.lineage_locked('women_tree')));
`);
// members_masked كما في الحي (20261112100000)
const MM = readFileSync(`${REPO}/migrations/20261112100000_members_masked_fast.sql`, 'utf8');
await db.exec(MM.slice(MM.indexOf('create or replace view')) + `\ngrant select on public.members_masked to authenticated;`);

const md5s = async () => Object.fromEntries((await db.query(`select p.oid::regprocedure::text s, md5(pg_get_functiondef(p.oid)) m
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('public', 'private')`)).rows.map(r => [r.s, r.m]));
const viewDef = async () => (await db.query(`select pg_get_viewdef('public.members_masked'::regclass) d`)).rows[0].d;
const policies = async () => (await db.query(`select tablename || '.' || policyname p from pg_policies order by 1`)).rows.map(r => r.p).join();
const as = async (who, sql, params) => {
  await db.exec(`select set_config('request.jwt.claim.sub', '${who ?? ''}', false); set role ${who ? 'authenticated' : 'anon'};`);
  try { return await db.query(sql, params); } finally { await db.exec(`reset role; select set_config('request.jwt.claim.sub', '', false);`); }
};
const one = async (who, sql, params) => Object.values((await as(who, sql, params)).rows[0])[0];
const set = async (who, value) => {
  try { return { ok: true, r: (await as(who, `select public.set_app_config('member_category_access', $1::jsonb) r`, [value])).rows[0].r }; }
  catch (e) { return { ok: false, code: e.code, hint: e.hint, msg: e.message }; }
};
const sees = (who, key) => one(who, `select public.member_access_allows($1)`, [key]);
const count = (who, t) => one(who, `select count(*)::int from public.${t}`);
const phoneOf = async (who, target) => (await as(who, `select phone_number from public.members_masked where id = $1`, [target])).rows[0]?.phone_number ?? null;
const tryInsert = async (who, sql) => { try { await as(who, sql); return true; } catch (e) { return e.code; } };

const BEFORE = await md5s();
const VIEW0 = await viewDef();
const POL0 = await policies();
// قبل الترحيل: المحدود مقفول عن الأربعة، والعضو يرى رقم غيره الظاهر
ok(await count(LIM, 'diwaniyas') === 0 && await count(M, 'diwaniyas') === 1, 'قبل: المحدود بلا ديوانيات، العضو يراها');
ok(await phoneOf(M, DS) === '+96550000007', 'قبل: العضو يرى الرقم الظاهر');

// ══════════ الترحيل ══════════
await db.exec(MIG);
const row = (await db.query(`select value, default_value, kind, category, is_public from public.app_config where key = 'member_category_access'`)).rows[0];
ok(row?.kind === 'json' && row.is_public === false && JSON.stringify(row.default_value) === '{}', 'المفتاح أُضيف (json، ليس عاماً، الافتراضي {})');
ok(JSON.stringify(Object.keys(row.value)) === '["limited"]'
   && ['diwaniyas', 'projects', 'library', 'women_tree', 'member_details'].every(k => row.value.limited[k] === false),
   'القيمة الأولى تطوي القائمة القديمة في «limited»', JSON.stringify(row.value));
ok((await as(M, `select public.app_config() c`)).rows[0].c.values.member_category_access !== undefined, 'يصل كل مسجّل عبر app_config()');

// ══════════ الفئة ══════════
const cats = { [O]: 'staff', [A]: 'staff', [MON]: 'staff', [S]: 'staff', [M]: 'family_man', [W]: 'family_woman', [DS]: 'daughter_son',
  [DD]: 'daughter_daughter', [LIM]: 'limited', [OSW]: 'outside_spouse', [OSH]: 'outside_spouse', [DDN]: 'daughter_daughter',
  [PEND]: null, [FROZ]: null };
for (const [who, want] of Object.entries(cats)) {
  ok(await one(who, `select public.my_member_category()`) === want, `الفئة: ${want ?? 'خارج الجدول'} (${who.slice(-2)})`);
}
ok(await one(null, `select 1`) === 1 && (await (async () => { try { await as(null, `select public.my_member_category()`); return false; } catch { return true; } })()),
   'غير المسجّل لا يستدعيها');

// ══════════ لا يتغيّر شيء على أحد (الافتراضي = اليوم) ══════════
ok(await count(LIM, 'diwaniyas') === 0 && await count(LIM, 'projects') === 0 && await count(LIM, 'family_archive') === 0
   && await count(LIM, 'women_members') === 0, 'المحدود: الأربعة مقفولة كما كانت');
ok(await count(M, 'diwaniyas') === 1 && await count(W, 'women_members') === 6 && await count(DS, 'projects') === 1
   && await count(OSW, 'family_archive') === 1, 'الباقون كما كانوا');
ok(await count(S, 'diwaniyas') === 1, 'المشرف (له صفّ محدود) لا يُقفل');
ok(await phoneOf(M, DS) === '+96550000007' && await phoneOf(LIM, DS) === null && await phoneOf(LIM, LIM) === null,
   'الرقم: العضو يراه، والمحدود (تفاصيل العضو مطفأة) لا');
ok(await phoneOf(O, W) === '+96550000006' && await phoneOf(M, W) === null, 'المالك يرى رقم المرأة المخفي، والعضو لا (كما كان)');

// ══════════ التعديل: المالك وحده ══════════
const cfg0 = row.value;
let r = await set(A, JSON.stringify({ ...cfg0, family_man: { tree: false } }));
ok(!r.ok && r.code === '42501', 'المدير لا يعدّل (42501)', JSON.stringify(r));
r = await set(M, JSON.stringify({ family_man: { diwaniyas: true } }));
ok(!r.ok && r.code === '42501', 'العضو لا يفتح لنفسه شيئاً');
let direct = null;
try { await as(M, `update public.app_config set value = '{}' where key = 'member_category_access'`); } catch (e) { direct = e; }
ok(!!direct, 'ولا كتابة مباشرة من التطبيق');

r = await set(O, JSON.stringify({ ...cfg0, daughter_son: { 'member_details.contact': false, diwaniyas: false, 'news.comment': false } }));
ok(r.ok, 'المالك يطفئ لابن البنت: الهاتف والديوانيات والتعليق', JSON.stringify(r));
ok(await phoneOf(DS, M) === null && await phoneOf(DS, DS) === '+96550000007', 'ابن البنت: رقم غيره مخفي من السيرفر، ورقمه هو ظاهر');
ok(await phoneOf(DD, M) === '+96550000005', 'بنت البنت لا تتأثر');
ok(await count(DS, 'diwaniyas') === 0 && await count(DD, 'diwaniyas') === 1, 'الديوانيات مقفولة على ابن البنت وحده');
ok(await tryInsert(DS, `insert into public.news_comments (content) values ('x')`) === '42501'
   && await tryInsert(DD, `insert into public.news_comments (content) values ('x')`) === true, 'التعليق: يُمنع على ابن البنت فقط');
ok(await tryInsert(DS, `insert into public.diwaniyas (title) values ('x')`) === '42501', 'الأم المطفأة تمنع «إضافة ديوانية» أيضاً');
ok(await sees(DS, 'diwaniyas.add') === false && await sees(DS, 'member_details.kinship') === true, 'الأم المطفأة تخفي أبناءها فقط');

// الإبلاغ والحظر دائماً
ok(await sees(DS, 'member_details.report') === true && await sees(LIM, 'member_details.block') === true
   && await sees(LIM, 'news.report') === true, 'الإبلاغ والحظر ظاهران لكل فئة ولو أمّهما مطفأة');
ok(await sees(LIM, 'profile.qr') === true, '«حسابي» لا يُخفى بنفسه');

// المحدود: الجدول يغلب، والقديم احتياط لما لا يذكره
r = await set(O, JSON.stringify({ limited: { diwaniyas: true } }));
ok(r.ok && await count(LIM, 'diwaniyas') === 1 && await count(LIM, 'projects') === 0, 'المحدود: فتح الديوانيات من الجدول، والمشاريع من القديم');
await db.exec(`update public.app_config set value = '["projects"]' where key = 'outside_member_locked_sections'`);
ok(await count(LIM, 'family_archive') === 1 && await count(LIM, 'projects') === 0, 'تغيير القديم ما زال يعمل احتياطاً');
await db.exec(`update public.app_config set value = '"x"' where key = 'outside_member_locked_sections'`);
ok(await count(LIM, 'women_members') === 0, 'القديم التالف = القائمة الافتراضية');
await db.exec(`update public.app_config set value = '["diwaniyas", "projects", "library", "women_tree", "member_details"]' where key = 'outside_member_locked_sections'`);

// حالة «استكمال التسجيل» لابن البنت كما هي
await db.exec(`update public.daughter_son_lineage set completed_at = null where profile_id = '${DS}'`);
ok(await count(DS, 'projects') === 0 && await one(DS, `select public.my_member_category()`) === 'daughter_son',
   'ابن بنت لم يكمل: القفل القديم كما هو');
await db.exec(`update public.daughter_son_lineage set completed_at = now() where profile_id = '${DS}'`);

// ══════════ الفحص يرفض ══════════
const bad = [
  [{ family_man: { 'member_details.report': false } }, 'مفتاح إبلاغ'],
  [{ family_man: { 'news.block_author': false } }, 'مفتاح حظر'],
  [{ limited: { block: false } }, 'الحظر نفسه'],
  [{ family_man: { profile: false } }, '«حسابي» نفسه'],
  [{ staff: { tree: false } }, 'فئة الإدارة'],
  [{ owner: {} }, 'فئة غير معروفة'],
  [{ family_man: { trees: false } }, 'شاشة بخطأ إملائي'],
  [{ family_man: { tree: 'no' } }, 'قيمة نصية'],
  [{ family_man: { tree: 0 } }, 'قيمة رقمية'],
  [{ family_man: ['tree'] }, 'صفّ قائمة لا كائن'],
  [[], 'قائمة بدل كائن'],
];
for (const [v, why] of bad) {
  const x = await set(O, JSON.stringify(v));
  ok(!x.ok && x.code === '22023' && x.hint === 'bad_value', `يُرفض: ${why}`, JSON.stringify(x));
}
const msg = await set(O, JSON.stringify({ family_man: { 'member_details.report': false } }));
ok(/الإبلاغ والحظر يظهران للجميع دائماً/.test(msg.msg ?? ''), 'رسالة الرفض بالعربي', msg.msg);
let d2 = null;
try { await db.exec(`update public.app_config set value = '{"family_man": {"member_details.block": false}}' where key = 'member_category_access'`); }
catch (e) { d2 = e; }
ok(d2?.code === '22023', 'حتى صيانة SQL تمرّ بالفحص');
ok((await set(O, JSON.stringify({ family_woman: {} }))).ok, 'صفّ فارغ مقبول (= الافتراضي)');
r = await set(O, 'null');
ok(r.r?.is_default === true && JSON.stringify(r.r.value) === '{}', 'null يرجعه للافتراضي {}');
ok(await count(LIM, 'diwaniyas') === 0, 'وبعده المحدود من القائمة القديمة كما كان');

// إعادة التطبيق لا تمسّ اختيار المالك
await set(O, JSON.stringify({ family_man: { contact: false } }));
await db.exec(MIG);
ok(JSON.stringify((await db.query(`select value from public.app_config where key = 'member_category_access'`)).rows[0].value)
   === '{"family_man":{"contact":false}}', 'إعادة التطبيق لا تمسّ اختيار المالك');

// ══════════ 20261127210000: «لم يستكمل التسجيل» ══════════
const MID = await md5s();
const catOf = who => one(who, `select public.my_member_category()`);
const tables = ['diwaniyas', 'projects', 'family_archive', 'women_members'];
const seen = async who => Promise.all(tables.map(t => count(who, t)));
const INC0 = JSON.stringify(await seen(INC)), INCF0 = JSON.stringify(await seen(INCF)), REV0 = JSON.stringify(await seen(REV));
ok(await catOf(INC) === 'daughter_son' && await catOf(INCF) === 'daughter_daughter', 'قبل: لم يستكمل = ابن/بنت بنت');
await db.exec(MIG2);
ok(await catOf(INC) === 'incomplete', '«لم يستكمل التسجيل»: ابن بنت بلا completed_at ولا limited_at');
ok(await catOf(INCF) === 'incomplete', '«لم يستكمل التسجيل»: بنت بنت أرسلت اسم الوالدة وتنتظر');
ok(await catOf(REV) === 'daughter_son', 'حساب المراجعة يبقى في فئته اليوم');
ok(await catOf(LIM) === 'limited' && await catOf(DS) === 'daughter_son' && await catOf(DD) === 'daughter_daughter'
   && await catOf(S) === 'staff' && await catOf(M) === 'family_man' && await catOf(DDN) === 'daughter_daughter',
   'المحدود أولاً، ومن استكمل والباقون كما كانوا');
ok(JSON.stringify(await seen(INC)) === INC0 && JSON.stringify(await seen(INCF)) === INCF0 && JSON.stringify(await seen(REV)) === REV0,
   'الافتراضي = اليوم: ما يراه «لم يستكمل» لم يتغيّر (قفل «استكمال التسجيل» كما هو)', `${INC0} ${JSON.stringify(await seen(INC))}`);
ok(await sees(INC, 'news.comment') === true && await sees(INC, 'member_details.contact') === true, 'بلا صفّ في الجدول: كل الخانات ظاهرة');
const cfgB = (await db.query(`select value from public.app_config where key = 'member_category_access'`)).rows[0].value;
r = await set(O, JSON.stringify({ ...cfgB, incomplete: { 'news.comment': false } }));
ok(r.ok, 'الفحص يقبل الفئة الجديدة، والمالك يعدّلها', JSON.stringify(r));
ok(await tryInsert(INC, `insert into public.news_comments (content) values ('x')`) === '42501'
   && await tryInsert(DS, `insert into public.news_comments (content) values ('x')`) === true
   && await tryInsert(REV, `insert into public.news_comments (content) values ('x')`) === true,
   'المطفأ لـ«لم يستكمل» يُمنع عليه وحده (لا ابن البنت المستكمل ولا حساب المراجعة)');
await db.exec(`update public.daughter_son_lineage set completed_at = now() where profile_id = '${INC}'`);
ok(await catOf(INC) === 'daughter_son', 'بعد اعتماد الإدارة يعود ابن بنت تلقائياً');
await db.exec(`update public.daughter_son_lineage set completed_at = null where profile_id = '${INC}'`);
r = await set(O, JSON.stringify({ incompletes: {} }));
ok(!r.ok && r.code === '22023', 'ما زالت الفئة غير المعروفة تُرفض');
await db.exec(MIG2);
ok(await catOf(INC) === 'incomplete', 'إعادة تطبيق 20261127210000 آمنة');
await db.exec(RB2);
const MID2 = await md5s();
ok(Object.keys(MID).every(k => MID2[k] === MID[k]) && Object.keys(MID2).every(k => MID[k]), 'تراجع 20261127210000: الدوال كما في 20261127190000 حرفياً',
   Object.keys(MID2).filter(k => MID2[k] !== MID[k]).join());
const cfgR = (await db.query(`select value from public.app_config where key = 'member_category_access'`)).rows[0].value;
ok(cfgR.incomplete === undefined && JSON.stringify(cfgR.family_man) === '{"contact":false}', 'تراجعه يحذف صفّ «incomplete» وحده', JSON.stringify(cfgR));
ok(await catOf(INC) === 'daughter_son' && (await set(O, JSON.stringify(cfgR))).ok, 'وبعده الفئة والفحص كما كانا');
await db.exec(MIG2);
await db.exec(RB2);

// ══════════ التراجع ══════════
await db.exec(RB);
const AFTER = await md5s();
ok(Object.keys(BEFORE).every(s => AFTER[s] === BEFORE[s]) && Object.keys(AFTER).every(s => BEFORE[s]), 'التراجع: الدوال كما كانت حرفياً',
   Object.keys(AFTER).filter(s => AFTER[s] !== BEFORE[s]).join());
ok(await viewDef() === VIEW0, 'التراجع: members_masked كما كانت حرفياً');
ok(await policies() === POL0, 'التراجع: السياسات كما كانت');
ok((await db.query(`select count(*)::int n from public.app_config where key = 'member_category_access'`)).rows[0].n === 0, 'التراجع: المفتاح حُذف');
ok(await count(LIM, 'diwaniyas') === 0 && await phoneOf(M, DS) === '+96550000007', 'التراجع: السلوك كما كان');

console.log(`\n${pass}/${pass + fail}`);
process.exit(fail ? 1 : 0);
