// تجربة 20261127260000_outside_husband_photo (صورة زوج البنت من خارج العائلة بلا حساب، موافقة المالك ٢٠٢٦-١١-٢٧) على
// قاعدة محلية معزولة (لا تلمس السيرفر). فوق نصّ الحي حرفياً (fixtures/live_2026-11-27: حارس الإدراج،
// decide_admin_request وجوهرها): قبل الترحيل (الطلب مرفوض) ← بعده (زوجته وابنه فقط، الإجراء add_photo فقط،
// الاسم من العقدة، الموافقة تكتب women_members للذكر فقط، مسار الملفات كما كان) ← بعد التراجع (النصّان كما في الحي).
// التشغيل: cd supabase/tests/family_links && node outside_husband_photo.test.mjs
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
process.on('unhandledRejection', e => { console.log('خطأ:', e.message, e.where ?? '', (e.query ?? '').slice(0, 300)); process.exit(2); });
const REPO = fileURLToPath(new URL('../../', import.meta.url));
const FIX = fileURLToPath(new URL('./fixtures/live_2026-11-27/', import.meta.url));
const base = readFileSync(new URL('./base.sql', import.meta.url), 'utf8');
const [baseBody] = base.split('-- ─── المشغّلات');
const fixture = n => readFileSync(`${FIX}${n}.sql`, 'utf8');
const MIG = '20261127260000_outside_husband_photo';
const mig = readFileSync(`${REPO}/migrations/${MIG}.sql`, 'utf8');
const rb = readFileSync(`${REPO}/rollback/${MIG}_rollback.sql`, 'utf8');

// ما تحتاجه الدوال الثلاث من الحي: أعمدة الطلب وشجرة النساء، ودالتان مساعدتان مصغّرتان
const live = `
create schema if not exists private;
alter table public.admin_requests add column details text, add column new_value text, add column admin_reply text,
  add column replied_at timestamptz, add column replied_by uuid, add column created_at timestamptz default now();
alter table public.women_members add column is_outside_family boolean default false;
create table public.news (id uuid primary key default gen_random_uuid());
create or replace function public.is_approved_member() returns boolean language sql stable as $$
  select coalesce(public.current_user_role() in ('owner','admin','monitor','supervisor','member'), false) $$;
create or replace function public.can_handle_admin_request(t text) returns boolean language sql stable as $$
  select coalesce(public.current_user_role() in ('owner','admin','monitor'), false) $$;
grant usage on schema auth to authenticated, anon;
grant select, insert on all tables in schema public to authenticated;
`;

const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
// O مالك · A مدير · F أب (ملف) · DP حساب البنت · D عقدتها (زوجها H) · H زوج من خارج العائلة بلا حساب ·
// SP حساب الابن · S عقدته (أبوه H) · X عضو لا علاقة له · W أنثى من خارج العائلة (للحارس الأخير)
const P = { O: id(1), A: id(2), F: id(3), DP: id(4), D: id(5), H: id(6), SP: id(7), S: id(8), X: id(9), W: id(10) };
let pass = 0, fail = 0;
const check = (l, ok, x = '') => { ok ? pass++ : fail++; console.log(`${ok ? '✅' : '❌'} ${l}${x ? ' — ' + x : ''}`); };

const db = new PGlite();
await db.exec(baseBody);
await db.exec(live);
for (const f of ['guard_admin_request_insert', 'decide_admin_request_core', 'decide_admin_request']) await db.exec(fixture(f));
await db.exec(`create trigger trg_guard_admin_request_insert before insert on public.admin_requests
  for each row execute function public.guard_admin_request_insert();`);
await db.exec(`
  insert into profiles(id, first_name, full_name, gender, role, status) values
    ('${P.O}', 'مالك', 'المالك', 'male', 'owner', 'active'), ('${P.A}', 'مدير', 'المدير', 'male', 'admin', 'active'),
    ('${P.F}', 'خالد', 'خالد المحمدعلي', 'male', 'member', 'active'),
    ('${P.DP}', 'سارة', 'سارة خالد', 'female', 'member', 'active'),
    ('${P.SP}', 'علي', 'علي حمد', 'male', 'member', 'active'),
    ('${P.X}', 'ناصر', 'ناصر', 'male', 'member', 'active');
  insert into women_members(id, first_name, full_name, gender) values ('${P.F}', 'خالد', 'خالد المحمدعلي', 'male');
  insert into women_members(id, first_name, full_name, gender, is_outside_family) values
    ('${P.H}', 'حمد', 'حمد الصالح', 'male', true), ('${P.W}', 'منى', 'منى الصالح', 'female', true);
  insert into women_members(id, first_name, full_name, parent_id, husband_id, gender, linked_user_id) values
    ('${P.D}', 'سارة', 'سارة خالد', '${P.F}', '${P.H}', 'female', '${P.DP}');
  insert into women_members(id, first_name, full_name, parent_id, mother_id, gender, linked_user_id) values
    ('${P.S}', 'علي', 'علي حمد', '${P.H}', '${P.D}', 'male', '${P.SP}');
  insert into auth.users(id) values ('${P.O}'), ('${P.A}'), ('${P.DP}'), ('${P.SP}'), ('${P.X}');`);

async function as(who, sql, params = []) {
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [JSON.stringify({ sub: who, role: 'authenticated' })]);
  await db.exec('set role authenticated');
  try { return { ok: true, rows: (await db.query(sql, params)).rows }; }
  catch (e) { return { ok: false, err: e.message, hint: e.hint }; }
  finally { await db.exec('reset role'); }
}
const url = who => `https://poxyxsgvzwmnmewytsiw.supabase.co/storage/v1/object/public/avatars/photo_suggestion_${who}_${id(77)}.jpg`;
const send = (who, member, target, action = 'add_photo', photo = url(who)) => as(who,
  `insert into public.admin_requests(member_id, requester_id, request_type, status, details)
   values ($1, $2, 'tree_edit', 'pending', $3) returning id, details`,
  [member, who, JSON.stringify({ v: 1, action, targetMemberId: target, targetMemberName: 'اسم من العميل', newPhotoUrl: photo })]);
const decide = (who, req) => as(who, `select public.decide_admin_request($1, 'approve') r`, [req]);
const node = async x => (await db.query(`select avatar_url, photo_url from women_members where id = $1`, [x])).rows[0];
const fnText = async sig => (await db.query(`select pg_get_functiondef($1::regprocedure) d`, [sig])).rows[0].d;
const guardLive = await fnText('public.guard_admin_request_insert()');
const coreLive = await fnText('private.decide_admin_request_core(uuid,text,text,jsonb)');

// ─── قبل الترحيل ───
const pre = await send(P.DP, P.DP, P.H);
check('قبل الترحيل: طلب صورة الزوج بلا حساب مرفوض', !pre.ok && /target_mismatch/.test(pre.err), pre.err);

await db.exec(mig);
console.log('\n══════ بعد الترحيل ══════');

const wife = await send(P.DP, P.DP, P.H);
check('زوجته: الطلب يُقبل', wife.ok, wife.err);
const det = wife.ok ? JSON.parse(wife.rows[0].details) : {};
check('الاسم المعروض من عقدة الزوج (لا من العميل ولا من ملفها)', det.targetMemberName === 'حمد الصالح', det.targetMemberName);
const son = await send(P.SP, P.SP, P.H);
check('ابنه: الطلب يُقبل', son.ok, son.err);
const other = await send(P.X, P.X, P.H);
check('عضو لا علاقة له: مرفوض', !other.ok && /target_mismatch/.test(other.err), other.err);
const asOther = await send(P.DP, P.X, P.H);
check('member_id غير مقدّم الطلب: مرفوض', !asOther.ok, asOther.err);
const notOutside = await send(P.DP, P.DP, P.F);
check('عقدة لها ملف (ليست من خارج العائلة): مرفوض', !notOutside.ok && /target_mismatch/.test(notOutside.err), notOutside.err);
const otherAct = await send(P.DP, P.DP, P.H, 'edit_name');
check('إجراء غير الصورة على العقدة: مرفوض', !otherAct.ok && /target_mismatch/.test(otherAct.err), otherAct.err);
const badUrl = await send(P.DP, P.DP, P.H, 'add_photo', url(P.SP));
check('رابط صورة ليس من رفع مقدّم الطلب: مرفوض', !badUrl.ok && /photo_invalid/.test(badUrl.err), badUrl.err);

// ─── الموافقة ───
const ok1 = await decide(P.A, wife.rows[0].id);
check('موافقة المدير: نجاح', ok1.ok && ok1.rows[0].r.ok === true, ok1.err);
const h = await node(P.H);
check('الصورة على عقدة الزوج (avatar_url و photo_url)', h.avatar_url === url(P.DP) && h.photo_url === url(P.DP), JSON.stringify(h));
const note = (await db.query(`select body from notifications where target_member_id = $1 order by created_at desc limit 1`, [P.DP])).rows[0];
check('إشعار صاحبة الطلب باسم الزوج', note?.body === 'تم اعتماد الصورة لـ «حمد الصالح»', note?.body);

// ─── مسار الملفات كما كان ───
const prof = await send(P.DP, P.F, P.F);
check('صورة لملف في profiles: الطلب كما كان', prof.ok, prof.err);
const ok2 = await decide(P.A, prof.rows[0].id);
const f = (await db.query(`select avatar_url from profiles where id = $1`, [P.F])).rows[0];
check('الموافقة تكتب profiles.avatar_url كما كانت', ok2.ok && f.avatar_url === url(P.DP), ok2.err ?? f.avatar_url);

// ─── الأنثى بلا صورة أبداً (طلب أُدرج بلا حارس — صيانة) ───
const forged = (await db.query(`insert into public.admin_requests(member_id, requester_id, request_type, status, details)
  values ($1, $1, 'tree_edit', 'pending', $2) returning id`,
  [P.DP, JSON.stringify({ v: 1, action: 'add_photo', targetMemberId: P.W, newPhotoUrl: url(P.DP) })])).rows[0];
const ok3 = await decide(P.A, forged.id);
const w = await node(P.W);
check('عقدة أنثى: الموافقة ترفض (bad_payload) ولا صورة', !ok3.ok && ok3.hint === 'bad_payload' && !w.avatar_url && !w.photo_url, ok3.err);
const st = (await db.query(`select status from admin_requests where id = $1`, [forged.id])).rows[0];
check('الطلب المرفوض يبقى معلّقاً', st.status === 'pending', st.status);

// ─── التراجع ───
await db.exec(rb);
check('بعد التراجع: الحارس كما في الحي حرفياً', await fnText('public.guard_admin_request_insert()') === guardLive);
check('بعد التراجع: الموافقة كما في الحي حرفياً', await fnText('private.decide_admin_request_core(uuid,text,text,jsonb)') === coreLive);
const post = await send(P.DP, P.DP, P.H);
check('بعد التراجع: طلب صورة الزوج بلا حساب مرفوض كما كان', !post.ok && /target_mismatch/.test(post.err), post.err);
const helper = (await db.query(`select count(*)::int n from pg_proc where proname = 'outside_husband_photo_ok'`)).rows[0].n;
check('بعد التراجع: الدالة المساعدة حُذفت', helper === 0);

console.log(`\nالنتيجة: ${pass} نجح، ${fail} فشل`);
process.exit(fail ? 1 : 0);
