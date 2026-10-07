// تجربة 20261007170000 (decide_admin_request — الموافقات من السيرفر، أ-٣) على قاعدة محلية معزولة (لا تلمس السيرفر).
// الطلبات تُنشأ كما تنشئها التطبيقات (عضو عبر حارس الإدراج الحي، والأنواع القديمة بصيانة SQL)، والقرار
// يُستدعى بدور authenticated + JWT المتصل. لكل نوع: قبول + رفض بالكتابات والإشعارات نفسها التي يكتبها
// الآيفون اليوم، والدور الخطأ مرفوض، والمعالَج سابقاً مرفوض، والحمولة الفاسدة مرفوضة بلا أي كتابة.
// التشغيل: cd supabase/tests/family_links && node decide_admin_request.test.mjs
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
const guard = readFileSync(`${REPO}/migrations/20261004200000_admin_requests_insert_guard.sql`, 'utf8');
const MIG = '20261007170000_decide_admin_request';
const mig = readFileSync(`${REPO}/migrations/${MIG}.sql`, 'utf8');
const rollback = readFileSync(`${REPO}/rollback/${MIG}_rollback.sql`, 'utf8');

// ─── نسخ الحي (٢٠٢٦-١٠-٠٧) لما تلمسه الدالة ───
const live = `
alter table public.admin_requests
  add column details text, add column new_value text, add column created_at timestamptz default now(),
  add column admin_reply text, add column replied_at timestamptz, add column replied_by uuid references public.profiles(id);
alter table public.admin_requests alter column request_type set default 'deceased_report', alter column status set default 'pending';
alter table public.notifications add column request_id uuid, add column request_type text, add column details jsonb,
  add column subject_member_id uuid references public.profiles(id) on delete set null;
alter table public.notifications alter column kind set default 'general', alter column kind set not null,
  alter column title set not null, alter column body set not null;
create table public.news (id uuid primary key default gen_random_uuid(), content text);
create unique index idx_profiles_phone_number_unique on public.profiles (phone_number)
  where phone_number is not null and phone_number <> '';
create or replace function public.is_approved_member() returns boolean language sql stable security definer
  set search_path to 'public' as $$
  select coalesce(public.current_user_role() = any(array['member','supervisor','monitor','admin','owner']), false); $$;
create or replace function public.can_handle_admin_request(p_type text) returns boolean language sql stable
  security definer set search_path to 'public' as $$
  select case public.current_user_role()
    when 'owner' then true when 'admin' then true
    when 'monitor' then coalesce(p_type, '') not in ('news_report', 'content_report')
    when 'supervisor' then coalesce(p_type, '') in ('news_report', 'content_report', 'contact_message')
    else false end; $$;
alter table public.admin_requests enable row level security;
create policy admin_requests_insert_self_or_moderator on public.admin_requests for insert
  with check ((auth.uid() is not null) and ((requester_id = auth.uid())
    or (public.current_user_role() = any (array['supervisor','admin','owner','monitor']))));
create policy admin_requests_select_moderator_or_owner on public.admin_requests for select
  using ((requester_id = auth.uid()) or (member_id = auth.uid())
    or (public.current_user_role() = any (array['supervisor','monitor','admin','owner'])));
create policy admin_requests_update_by_scope on public.admin_requests for update to authenticated
  using (public.can_handle_admin_request(request_type) and ((public.current_user_role() = 'owner')
    or ((requester_id is distinct from auth.uid()) and (member_id is distinct from auth.uid()))))
  with check (public.can_handle_admin_request(request_type));
create policy require_authenticated_admin_requests on public.admin_requests as restrictive for all
  using (auth.uid() is not null) with check (auth.uid() is not null);
grant usage on schema auth to authenticated, anon;
grant select, insert, update, delete on public.admin_requests to authenticated;

create or replace function public.normalize_kuwait_phone(raw text) returns text language plpgsql immutable
  set search_path to 'public' as $function$
declare clean text; digits text;
begin
  if raw is null then return null; end if;
  clean := btrim(raw);
  if clean = '' then return null; end if;
  digits := regexp_replace(clean, '[^0-9]', '', 'g');
  if clean like '00%' then digits := regexp_replace(digits, '^00', ''); end if;
  if digits = '' then return null; end if;
  if length(digits) = 8 then return '+965' || digits; end if;
  if length(digits) between 8 and 15 then return '+' || digits; end if;
  return null;
end; $function$;
create or replace function public.trg_profiles_normalize_phone() returns trigger language plpgsql
  set search_path to 'public' as $function$
begin new.phone_number := public.normalize_kuwait_phone(new.phone_number); return new; end; $function$;
create trigger profiles_0_normalize_phone before insert or update of phone_number on public.profiles
  for each row execute function public.trg_profiles_normalize_phone();

create or replace function public.trg_profiles_deceased_no_admin_role() returns trigger language plpgsql
  set search_path to 'public' as $function$
begin
  if coalesce(new.is_deceased, false) and new.role in ('admin', 'monitor', 'supervisor') then
    if tg_op = 'UPDATE' and new.role is not distinct from old.role then new.role := 'member';
    else raise exception 'deceased_cannot_hold_role' using hint = 'لا يمكن تعيين دور إداري لعضو متوفى'; end if;
  end if;
  return new;
end; $function$;
create trigger trg_zz_deceased_no_admin_role before insert or update of is_deceased, role on public.profiles
  for each row execute function public.trg_profiles_deceased_no_admin_role();

create or replace function public.set_family_name_cascade(p_member_id uuid, p_family text) returns integer
  language plpgsql security definer set search_path to 'public' as $function$
declare affected int;
begin
  if coalesce(public.current_user_role(), '') not in ('owner', 'admin', 'monitor') then raise exception 'not_allowed'; end if;
  with recursive line as (
    select id from public.profiles where id = p_member_id
    union all
    select p.id from public.profiles p join line l on p.father_id = l.id)
  update public.profiles set family_name = nullif(trim(p_family), '') where id in (select id from line);
  get diagnostics affected = row_count;
  return affected;
end; $function$;

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
create or replace function public.fanout_broadcast_notification() returns trigger language plpgsql security definer
  set search_path to 'public' as $function$
begin
  if new.target_member_id is not null then return new; end if;
  if coalesce(new.kind, '') in ('admin_broadcast', 'app_update') then
    insert into public.notifications (target_member_id, title, body, kind, created_by, created_at, is_read,
       request_id, request_type, details, subject_member_id)
    select p.id, new.title, new.body, new.kind, new.created_by, coalesce(new.created_at, timezone('utc', now())), false,
           new.request_id, new.request_type, new.details, new.subject_member_id
    from public.profiles p where coalesce(p.role, '') <> 'pending'
      and exists (select 1 from public.device_tokens d where d.member_id = p.id);
    return new;
  end if;
  insert into public.notifications (target_member_id, title, body, kind, created_by, created_at, is_read,
     request_id, request_type, details, subject_member_id)
  select p.id, new.title, new.body, new.kind, new.created_by, coalesce(new.created_at, timezone('utc', now())), false,
         new.request_id, new.request_type, new.details, new.subject_member_id
  from public.profiles p where p.role in ('owner', 'admin', 'monitor', 'supervisor');
  return null;
end; $function$;
create or replace function public.notifications_fill_subject() returns trigger language plpgsql security definer
  set search_path to 'public' as $function$
begin
  if new.subject_member_id is null and new.request_id is not null then
    select coalesce(r.member_id, r.requester_id) into new.subject_member_id from public.admin_requests r where r.id = new.request_id;
  end if;
  return new;
end; $function$;
create trigger trg_a_guard_notification_sender before insert on public.notifications for each row execute function public.guard_notification_sender();
create trigger trg_fanout_broadcast_notification before insert on public.notifications for each row execute function public.fanout_broadcast_notification();
create trigger trg_notifications_fill_subject before insert on public.notifications for each row execute function public.notifications_fill_subject();
`;

const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const P = { O: id(1), A: id(2), A2: id(3), MON: id(4), S: id(5), FA: id(6), M1: id(10), M2: id(11), T: id(12), T2: id(13),
  PEND: id(14), DEAD: id(15), LU: id(16), G: id(17), N1: id(80), N2: id(81) };
const STAFF = 6; // O, A, A2, MON, S, FA — نسخ إعلان الإدارة (fanout يشمل كل الأدوار الإدارية)
const NAME = { T: 'طاهر صلاح المحمدعلي', M1: 'حسن صلاح المحمدعلي', T2: 'تركي صلاح', DEAD: 'جد متوفى' };
const PHOTO = (uid, u = 'c0ffee00-1234-4abc-8def-0123456789ab') =>
  `https://poxyxsgvzwmnmewytsiw.supabase.co/storage/v1/object/public/avatars/photo_suggestion_${uid}_${u}.jpg`;
const iosJSON = o => JSON.stringify(o).replaceAll('/', '\\/'); // JSONEncoder في الآيفون يهرّب «/»
const U = s => s.toUpperCase();

let pass = 0, fail = 0;
const canon = v => JSON.stringify(v, (k, x) => x && typeof x === 'object' && !Array.isArray(x) ? Object.fromEntries(Object.keys(x).sort().map(key => [key, x[key]])) : x);
const same = (a, b) => canon(a) === canon(b);
const check = (l, ok, x = '') => { ok ? pass++ : fail++; console.log(`${ok ? '✅' : '❌'} ${l}${x ? ' — ' + x : ''}`); };

const db = new PGlite();
await db.exec(baseBody); await db.exec(preFns); await db.exec(baseTriggers); await db.exec(links);
await db.exec(live); await db.exec(guard); await db.exec(mig);
await db.exec(`
  insert into profiles(id, first_name, full_name, gender, role, status) values ('${P.G}', 'صلاح', 'صلاح الجد', 'male', 'member', 'active');
  insert into women_members(id, first_name, full_name, gender) values ('${P.G}', 'صلاح', 'صلاح الجد', 'male');
  insert into profiles(id, first_name, full_name, gender, role, status, phone_number, is_deceased) values
    ('${P.O}', 'مالك', 'المالك', 'male', 'owner', 'active', null, false),
    ('${P.A}', 'بدر', 'بدر المدير', 'male', 'admin', 'active', null, false),
    ('${P.A2}', 'خالد', 'خالد المدير', 'male', 'admin', 'active', null, false),
    ('${P.MON}', 'علي', 'علي المراقب', 'male', 'monitor', 'active', null, false),
    ('${P.S}', 'سعد', 'سعد المشرف', 'male', 'supervisor', 'active', null, false),
    ('${P.FA}', 'مجمّد', 'مدير مجمّد', 'male', 'admin', 'frozen', null, false),
    ('${P.M1}', 'حسن', '${NAME.M1}', 'male', 'member', 'active', null, false),
    ('${P.M2}', 'علي', 'علي صلاح', 'male', 'member', 'active', null, false),
    ('${P.T}', 'طاهر', '${NAME.T}', 'male', 'member', 'active', '+96550000001', false),
    ('${P.T2}', 'تركي', '${NAME.T2}', 'male', 'member', 'active', '+96550000002', false),
    ('${P.PEND}', 'جديد', 'مسجّل معلّق', 'male', 'pending', 'pending', null, false),
    ('${P.DEAD}', 'جد', '${NAME.DEAD}', 'male', 'member', 'active', null, true);
  update profiles set father_id = '${P.G}' where id in ('${P.M1}', '${P.M2}');
  insert into auth.users(id) values ('${P.O}'), ('${P.A}'), ('${P.A2}'), ('${P.MON}'), ('${P.S}'), ('${P.FA}'),
    ('${P.M1}'), ('${P.M2}'), ('${P.T}'), ('${P.PEND}');
  insert into auth.users(id, raw_app_meta_data) values ('${P.LU}', '{"profile_id": "${P.A2}"}');
  insert into news(id, content) values ('${P.N1}', 'خبر ١'), ('${P.N2}', 'خبر ٢');
  grant select, insert, update on public.profiles to authenticated;`);
const q = async (sql, params = []) => (await db.query(sql, params)).rows;
const one = async (sql, params = []) => (await q(sql, params))[0];

// المتصل: uuid · {sub, pid} (حساب منقول) · 'anon' · 'noclaims' · 'maint' (صيانة SQL)
async function as(who, sql, params = []) {
  const claims = who === 'maint' || who === 'anon' || who === 'noclaims' ? (who === 'noclaims' ? JSON.stringify({ role: 'authenticated' }) : '')
    : JSON.stringify(typeof who === 'string' ? { sub: who, role: 'authenticated' } : { sub: who.sub, role: 'authenticated', app_metadata: { profile_id: who.pid } });
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [claims]);
  if (who !== 'maint') await db.exec(`set role ${who === 'anon' ? 'anon' : 'authenticated'}`);
  try { return { ok: true, rows: (await db.query(sql, params)).rows }; }
  catch (e) { return { ok: false, err: e.message, hint: e.hint, code: e.code, detail: e.detail }; }
  finally { if (who !== 'maint') await db.exec('reset role'); await db.query(`select set_config('request.jwt.claims', '', false)`); }
}
async function mkreq(who, r) {
  const res = await as(who, `insert into public.admin_requests (member_id, requester_id, request_type, status, new_value, details)
    values ($1::uuid, $2::uuid, $3, $4, $5, $6) returning id`,
    [r.member, r.requester ?? (who === 'maint' ? r.member : who), r.type, r.status ?? 'pending', r.nv ?? null, r.details ?? null]);
  if (!res.ok) throw new Error(`إنشاء الطلب فشل (${r.type}): ${res.err}`);
  return res.rows[0].id;
}
async function decide(who, rid, decision, reason = null, overrides = null) {
  await db.exec('delete from notifications');
  const r = await as(who, `select public.decide_admin_request($1::uuid, $2, $3, $4::jsonb) as r`,
    [rid, decision, reason, overrides == null ? null : JSON.stringify(overrides)]);
  return r.ok ? { ok: true, res: r.rows[0].r } : r;
}
const status = async rid => (await one(`select status from admin_requests where id = $1`, [rid]))?.status;
const prof = async pid => one(`select * from profiles where id = $1`, [pid]);
const toRequester = async rid => q(`select n.* from notifications n join admin_requests r on r.id = $1
  where n.target_member_id = r.requester_id and n.kind in ('admin', 'request_rejected')`, [rid]);
// نشاط شجرة النساء (women_add/women_delete) يكتبه مشغّل log_women_change_to_activity كما مع كتابة التطبيق
const bcast = async () => q(`select * from notifications where kind not in ('admin', 'request_rejected') and kind not like 'women\\_%' order by target_member_id`);
const refused = (label, r, hint) => check(`${label}: مرفوض (${hint})`, !r.ok && r.hint === hint, r.err ?? JSON.stringify(r.res));
const te = o => iosJSON({ v: 3, ...o });

// إشعار صاحب الطلب + إعلان الإدارة كما يكتبهما الآيفون
async function expectNotes(label, rid, { req, b, bKind }) {
  const n = await toRequester(rid);
  if (req) check(`${label}: إشعار صاحب الطلب «${req.title}»`, n.length === 1 && n[0].title === req.title && n[0].body === req.body
      && n[0].kind === (req.kind ?? 'admin'), JSON.stringify(n.map(x => [x.title, x.body, x.kind])));
  else check(`${label}: لا إشعار لصاحب الطلب`, n.length === 0, JSON.stringify(n.map(x => [x.title, x.body])));
  const bc = await bcast();
  if (b) check(`${label}: إعلان الإدارة «${b.title}» نسخة لكل إداري (${STAFF})`, bc.length === STAFF
      && bc.every(x => x.title === b.title && x.body === b.body && x.kind === bKind && x.target_member_id), JSON.stringify(bc[0] ? [bc.length, bc[0].title, bc[0].body, bc[0].kind] : []));
  else check(`${label}: لا إعلان للإدارة`, bc.length === 0, `${bc.length}`);
}

console.log('══════ ١) الرفض العام: الدخول والقرار والنوع والدور ونفسك والمعالَج ══════');
let rid = await mkreq(P.M1, { member: P.M1, type: 'name_change', nv: 'حسن صلاح' });
let r = await as('anon', `select public.decide_admin_request($1::uuid, 'approve') as r`, [rid]);
check('anon لا يملك تنفيذ الدالة', !r.ok && /permission denied/.test(r.err), r.err);
r = await decide('noclaims', rid, 'approve'); refused('بلا مستخدم (JWT بلا sub)', r, 'not_authenticated');
r = await decide(P.A, rid, 'maybe'); refused('قرار غير معروف', r, 'bad_decision');
r = await decide(P.A, rid, null); refused('قرار فارغ', r, 'bad_decision');
r = await decide(P.A, id(999), 'approve'); refused('طلب غير موجود', r, 'request_not_found');
for (const t of ['link_request', 'join_request', 'contact_message', 'edit_request']) {
  const x = await mkreq('maint', { member: P.M2, type: t, details: 'x' });
  r = await decide(P.O, x, 'approve'); refused(`النوع ${t} يبقى في التطبيقات`, r, 'unsupported_type');
}
r = await decide(P.M2, rid, 'approve'); refused('عضو عادي', r, 'not_allowed');
r = await decide(P.FA, rid, 'approve'); refused('مدير مجمّد', r, 'not_allowed');
r = await decide(P.PEND, rid, 'approve'); refused('معلّق', r, 'not_allowed');
r = await decide(P.S, rid, 'approve'); refused('المشرف على طلب شجرة (تغيير اسم)', r, 'not_allowed');
r = await decide(P.S, rid, 'reject'); refused('المشرف يرفض طلب شجرة', r, 'not_allowed');
r = await decide(P.M1, rid, 'approve'); refused('صاحب الطلب نفسه (عضو)', r, 'not_allowed');
check('الطلب ما زال معلّقاً والاسم كما هو بعد كل الرفض', await status(rid) === 'pending' && (await prof(P.M1)).full_name === NAME.M1);
let own = await mkreq(P.A, { member: P.A, type: 'name_change', nv: 'بدر المدير الجديد' });
r = await decide(P.A, own, 'approve'); refused('المدير يقرّر طلبه هو', r, 'own_request');
r = await decide({ sub: P.LU, pid: P.A2 }, own, 'approve');
check('مدير آخر (حساب منقول app_metadata) يقرّر طلب المدير', r.ok && (await prof(P.A)).full_name === 'بدر المدير الجديد', r.err ?? '');
const ownA2 = await mkreq(P.A2, { member: P.A2, type: 'name_change', nv: 'خالد' });
r = await decide({ sub: P.LU, pid: P.A2 }, ownA2, 'approve'); refused('حساب منقول يقرّر طلب ملفه (current_profile_id)', r, 'own_request');
own = await mkreq(P.O, { member: P.O, type: 'name_change', nv: 'المالك' });
r = await decide(P.O, own, 'approve'); check('المالك يقرّر طلبه (كسياسة الإغلاق)', r.ok, r.err ?? '');
r = await decide(P.A, rid, 'approve'); check('المدير يقبل', r.ok, r.err ?? '');
r = await decide(P.A2, rid, 'approve'); refused('قبول ثانٍ لنفس الطلب', r, 'already_handled');
r = await decide(P.A2, rid, 'reject'); refused('رفض بعد القبول', r, 'already_handled');
const oldPath = await mkreq(P.M1, { member: P.M1, type: 'phone_change', nv: '+96550000077' });
await as(P.A, `update admin_requests set status = 'approved' where id = $1 and status = 'pending'`, [oldPath]);
r = await decide(P.A2, oldPath, 'approve'); refused('طلب أغلقته نسخة قديمة (كتابة مباشرة)', r, 'already_handled');
check('المسار القديم ما زال يعمل (لم يُسحب شيء)', await status(oldPath) === 'approved');
r = await decide(P.A, own, 'approve', null, { silent: true }); refused('طلب معالَج (حتى مع silent)', r, 'already_handled');
rid = await mkreq(P.M1, { member: P.M1, type: 'name_change', nv: 'حسن صلاح عبدالله' });
r = await decide(P.A, rid, 'approve', null, { silent: true }); refused('«بلا إشعارات» لغير قبول إضافة ابن', r, 'bad_payload');
r = await decide(P.A, rid, 'approve', null, { silent: true, x: 1 }); refused('مفاتيح غير معروفة', r, 'bad_payload');
r = await decide(P.A, rid, 'approve', null, ['silent']); refused('overrides ليست كائناً', r, 'bad_payload');
r = await decide(P.A, rid, 'approve', null, { silent: 'yes' }); refused('silent ليست منطقية', r, 'bad_payload');
check('ما زال معلّقاً', await status(rid) === 'pending');

console.log('\n══════ ٢) تغيير الاسم والعائلة ══════');
r = await decide(P.A, rid, 'approve');
let p = await prof(P.M1);
check('قبول تغيير الاسم: full_name + first_name (أول كلمة)', r.ok && p.full_name === 'حسن صلاح عبدالله' && p.first_name === 'حسن', JSON.stringify([p.full_name, p.first_name]));
check('النتيجة: approved + admin_push', r.res.status === 'approved' && r.res.admin_push?.kind === 'name_change' && r.res.requester_notified === true, JSON.stringify(r.res));
await expectNotes('قبول الاسم', rid, { req: { title: 'تم تغيير اسمك', body: 'تم اعتماد اسمك الجديد: حسن صلاح عبدالله' },
  b: { title: 'تم قبول تغيير اسم', body: 'وافقت الإدارة — تغيّر الاسم من «حسن صلاح» إلى «حسن صلاح عبدالله»' }, bKind: 'name_change' });
check('الطلب approved', await status(rid) === 'approved');
rid = await mkreq(P.M1, { member: P.M1, type: 'name_change', nv: 'اسم آخر' });
r = await decide(P.MON, rid, 'reject', '  الاسم غير مطابق  ');
check('المراقب يرفض تغيير الاسم', r.ok && await status(rid) === 'rejected' && (await prof(P.M1)).full_name === 'حسن صلاح عبدالله', r.err ?? '');
await expectNotes('رفض الاسم من المراقب', rid, { req: null,
  b: { title: 'تم رفض تغيير اسم', body: 'تم رفض طلب تغيير اسم «حسن صلاح عبدالله»' }, bKind: 'name_change' });
rid = await mkreq(P.M1, { member: P.M1, type: 'name_change', nv: 'اسم ثالث' });
r = await decide(P.A, rid, 'reject', 'الاسم غير مطابق');
await expectNotes('رفض الاسم من المدير', rid, { req: { title: 'لم يتم قبول طلبك', body: 'طلب تغيير الاسم لم تتم الموافقة عليه\nالسبب: الاسم غير مطابق', kind: 'request_rejected' },
  b: { title: 'تم رفض تغيير اسم', body: 'تم رفض طلب تغيير اسم «حسن صلاح عبدالله»' }, bKind: 'name_change' });
rid = await mkreq('maint', { member: P.M2, type: 'name_change', nv: '' });
r = await decide(P.A, rid, 'approve'); refused('تغيير اسم بلا اسم', r, 'bad_payload');
check('بلا كتابة، معلّق', await status(rid) === 'pending' && (await prof(P.M2)).full_name === 'علي صلاح');
// العائلة: العضو وأبناؤه
await db.exec(`insert into profiles(id, first_name, full_name, gender, role, status, father_id) values ('${id(20)}', 'ابن', 'ابن علي', 'male', 'member', 'active', '${P.M2}')`);
rid = await mkreq(P.M2, { member: P.M2, type: 'family_change', nv: 'الصالح' });
r = await decide(P.MON, rid, 'approve');
check('قبول تغيير العائلة (المراقب): العضو وابنه', r.ok && (await prof(P.M2)).family_name === 'الصالح' && (await prof(id(20))).family_name === 'الصالح', r.err ?? '');
check('تغيير العائلة: لا إعلان (admin_push = null)', r.res.admin_push === null, JSON.stringify(r.res));
await expectNotes('قبول العائلة من المراقب', rid, { req: null, b: null });
rid = await mkreq(P.M2, { member: P.M2, type: 'family_change', nv: 'العلي' });
r = await decide(P.O, rid, 'approve');
await expectNotes('قبول العائلة من المالك', rid, { req: { title: 'تم تغيير عائلتك', body: 'تم اعتماد عائلتك الجديدة: العلي' }, b: null });
rid = await mkreq(P.M2, { member: P.M2, type: 'family_change', nv: 'الحسن' });
r = await decide(P.A, rid, 'reject');
await expectNotes('رفض العائلة', rid, { req: { title: 'لم يتم قبول طلبك', body: 'طلب تغيير العائلة لم تتم الموافقة عليه', kind: 'request_rejected' },
  b: { title: 'تم رفض تغيير اسم', body: 'تم رفض طلب تغيير اسم «علي صلاح»' }, bKind: 'name_change' });
check('العائلة بعد الرفض كما هي', (await prof(P.M2)).family_name === 'العلي');

console.log('\n══════ ٣) تغيير الرقم ══════');
rid = await mkreq(P.M1, { member: P.M1, type: 'phone_change', nv: '+96551112222' });
r = await decide(P.A, rid, 'approve');
check('قبول: الرقم موحّد على الملف', r.ok && (await prof(P.M1)).phone_number === '+96551112222', r.err ?? '');
await expectNotes('قبول الرقم', rid, { req: { title: 'تم تغيير رقم هاتفك', body: 'رقم هاتفك الجديد تم اعتماده بنجاح' },
  b: { title: 'تم قبول تغيير رقم', body: 'تم تغيير رقم «حسن صلاح عبدالله»' }, bKind: 'phone_change' });
rid = await mkreq(P.M1, { member: P.M1, type: 'phone_change', nv: '50000002' });
r = await decide(P.A, rid, 'approve'); refused('رقم عضو آخر (آخر ٨ أرقام)', r, 'phone_in_use');
check('بلا كتابة، معلّق', await status(rid) === 'pending' && (await prof(P.M1)).phone_number === '+96551112222');
r = await decide(P.A, rid, 'reject', 'مكرر');
await expectNotes('رفض الرقم', rid, { req: { title: 'لم يتم قبول طلبك', body: 'طلب تغيير رقم الهاتف لم تتم الموافقة عليه\nالسبب: مكرر', kind: 'request_rejected' },
  b: { title: 'تم رفض تغيير رقم', body: 'تم رفض تغيير رقم «حسن صلاح عبدالله»' }, bKind: 'phone_change' });
rid = await mkreq('maint', { member: P.M2, type: 'phone_change', nv: '12' });
r = await decide(P.A, rid, 'approve'); refused('رقم غير صالح', r, 'bad_payload');
rid = await mkreq(P.M2, { member: P.M2, type: 'phone_change', nv: '0096551234567' });
r = await decide(P.MON, rid, 'approve');
check('المراقب يقبل: 00 → +', r.ok && (await prof(P.M2)).phone_number === '+96551234567', r.err ?? '');
await expectNotes('قبول الرقم من المراقب', rid, { req: null, b: { title: 'تم قبول تغيير رقم', body: 'تم تغيير رقم «علي صلاح»' }, bKind: 'phone_change' });

console.log('\n══════ ٤) إضافة ابن ══════');
const child = async (n, father, status = 'pending') => { await db.exec(`insert into profiles(id, first_name, full_name, gender, role, status, father_id, created_at)
  values ('${id(n)}', 'ابن${n}', 'ابن${n} حسن', 'male', 'member', '${status}', '${father}', now())`); return id(n); };
let c1 = await child(30, P.M1);
rid = await mkreq(P.M1, { member: P.M1, type: 'child_add', nv: U(c1), details: 'تمت إضافة ابن جديد: ابن30 (حي).' });
r = await decide(P.MON, rid, 'approve');
check('المراقب يقبل: الابن مفعّل', r.ok && (await prof(c1)).status === 'active', r.err ?? '');
await expectNotes('قبول الابن من المراقب', rid, { req: null,
  b: { title: 'تم قبول طلب إضافة ابن', body: 'تم إضافة «ابن30» لـ «حسن صلاح عبدالله»' }, bKind: 'child_add' });
let c2 = await child(31, P.M1);
rid = await mkreq(P.M1, { member: P.M1, type: 'child_add', nv: c2 });
r = await decide(P.A, rid, 'approve');
await expectNotes('قبول الابن من المدير', rid, { req: { title: 'تم قبول طلبك', body: 'تم إضافة الابن: «ابن31» لـ: «حسن صلاح عبدالله»' },
  b: { title: 'تم قبول طلب إضافة ابن', body: 'تم إضافة «ابن31» لـ «حسن صلاح عبدالله»' }, bKind: 'child_add' });
let c3 = await child(32, P.M1);
rid = await mkreq(P.M1, { member: P.M1, type: 'child_add', nv: c3 });
r = await decide(P.A, rid, 'approve', null, { silent: true });
check('القبول الجماعي (silent): مفعّل بلا أي إشعار', r.ok && (await prof(c3)).status === 'active' && r.res.admin_push === null
  && (await q(`select count(*)::int n from notifications`))[0].n === 0, r.err ?? JSON.stringify(r.res));
let c4 = await child(33, P.M1);
await db.exec(`update profiles set status = 'frozen' where id = '${c4}'`);
rid = await mkreq('maint', { member: P.M1, requester: P.M1, type: 'child_add', nv: c4 });
r = await decide(P.A, rid, 'approve');
check('ابن مجمّد لا يُفك بالقبول', r.ok && (await prof(c4)).status === 'frozen', r.err ?? '');
let c5 = await child(34, P.M1);
rid = await mkreq(P.M1, { member: P.M1, type: 'child_add', nv: c5 });
r = await decide(P.MON, rid, 'reject', 'خطأ');
check('المراقب يرفض: الطلب مرفوض والابن باقٍ (الحذف للمالك والمدير — كاليوم)', r.ok && await status(rid) === 'rejected' && !!(await prof(c5)), r.err ?? '');
await expectNotes('رفض الابن من المراقب', rid, { req: null, b: { title: 'تم رفض طلب إضافة ابن', body: 'تم رفض طلب إضافة «ابن34»\nالسبب: خطأ' }, bKind: 'child_add' });
let c6 = await child(35, P.M1);
rid = await mkreq(P.M1, { member: P.M1, type: 'child_add', nv: c6 });
r = await decide(P.A, rid, 'reject');
check('المدير يرفض: ملف الابن يُحذف', r.ok && !(await prof(c6)) && await status(rid) === 'rejected', r.err ?? '');
check('مشغّل نشاط شجرة النساء يعمل كما مع التطبيق (women_delete)', (await q(`select count(*)::int n from notifications where kind = 'women_delete'`))[0].n > 0);
await expectNotes('رفض الابن من المدير', rid, { req: null, b: { title: 'تم رفض طلب إضافة ابن', body: 'تم رفض طلب إضافة «ابن35»' }, bKind: 'child_add' });
let c7 = await child(36, P.M1);
rid = await mkreq(P.M1, { member: P.M1, type: 'child_add', nv: c7 });
await child(37, c7, 'active');
r = await decide(P.O, rid, 'reject');
check('رفض ابن له أبناء: حماية روابط العائلة ترفض والطلب يبقى معلّقاً', !r.ok && r.hint === 'family_links_protected' && await status(rid) === 'pending' && !!(await prof(c7)), r.err ?? '');
rid = await mkreq('maint', { member: P.M1, type: 'child_add', nv: 'not-a-uuid' });
r = await decide(P.A, rid, 'reject'); refused('رفض بابن ليس معرّفاً', r, 'bad_payload');
r = await decide(P.A, rid, 'approve');
check('قبول بابن ليس معرّفاً: يُغلق بلا تفعيل (كالآيفون)', r.ok && await status(rid) === 'approved', r.err ?? '');

console.log('\n══════ ٥) تأكيد وفاة (النوع القديم) ══════');
const W1 = id(40); await db.exec(`insert into profiles(id, first_name, full_name, gender, role, status) values ('${W1}', 'هند', 'هند صلاح', 'female', 'member', 'active')`);
rid = await mkreq('maint', { member: W1, requester: P.M1, type: 'deceased_report', details: 'طلب تأكيد وفاة بتاريخ: 2026-10-01' });
r = await decide(P.A, rid, 'approve');
p = await prof(W1);
check('قبول: متوفاة، بلا تاريخ (كالآيفون)', r.ok && p.is_deceased === true && p.death_date === null, r.err ?? '');
check('مربّع إعلان الوفاة', same(r.res.death_announcement, { name: 'هند صلاح', member_id: W1, death_date: null, is_female: true }), JSON.stringify(r.res.death_announcement));
await expectNotes('قبول الوفاة', rid, { req: { title: 'تم قبول طلبك', body: 'تم تأكيد حالة الوفاة وتحديث الشجرة' },
  b: { title: 'تم قبول طلب وفاة', body: 'تم تأكيد وفاة «هند صلاح»' }, bKind: 'deceased_report' });
rid = await mkreq('maint', { member: P.DEAD, requester: P.M1, type: 'deceased_report', details: 'x' });
r = await decide(P.MON, rid, 'approve');
check('متوفى أصلاً: لا مربّع إعلان', r.ok && r.res.death_announcement === null, JSON.stringify(r.res));
rid = await mkreq('maint', { member: P.T2, requester: P.M1, type: 'deceased_report', details: 'x' });
r = await decide(P.A, rid, 'reject', 'حي يرزق');
check('رفض: لا كتابة', r.ok && (await prof(P.T2)).is_deceased === false && await status(rid) === 'rejected', r.err ?? '');
await expectNotes('رفض الوفاة', rid, { req: null, b: { title: 'تم رفض طلب وفاة', body: `تم رفض طلب تأكيد وفاة «${NAME.T2}»\nالسبب: حي يرزق` }, bKind: 'deceased_report' });

console.log('\n══════ ٦) تعديل الشجرة (كل الإجراءات) ══════');
const tree = (o, who = P.M1, member = P.T) => mkreq(who, { member: U(member), type: 'tree_edit', details: te(o) });
const T = U(P.T);
rid = await tree({ action: 'edit_name', targetMemberId: T, targetMemberName: 'اسم مزوّر', newName: '  طاهر صالح المحمدعلي ' });
r = await decide(P.A, rid, 'approve');
p = await prof(P.T);
check('تعديل اسم: الاسم مقصوص + أول كلمة', r.ok && p.full_name === 'طاهر صالح المحمدعلي' && p.first_name === 'طاهر' && r.res.action === 'edit_name', r.err ?? JSON.stringify([p.full_name]));
await expectNotes('تعديل اسم', rid, { req: { title: 'تم قبول طلبك', body: 'تم تغيير الاسم إلى: «طاهر صالح المحمدعلي»' },
  b: { title: 'تم قبول تعديل اسم', body: `تم قبول طلب تعديل اسم لـ «${NAME.T}»` }, bKind: 'tree_edit' }); // الاسم المعروض من السيرفر (الحارس)
rid = await tree({ action: 'تعديل اسم', targetMemberId: T, newName: 'طاهر' }); // القديمة بالعربي
r = await decide(P.A, rid, 'approve');
check('الإجراء القديم «تعديل اسم»', r.ok && (await prof(P.T)).full_name === 'طاهر' && r.res.action === 'edit_name', r.err ?? '');
rid = await tree({ action: 'edit_phone', targetMemberId: T, newPhone: '+96550000003' });
r = await decide(P.MON, rid, 'approve');
check('تعديل رقم (المراقب)', r.ok && (await prof(P.T)).phone_number === '+96550000003' && r.res.requester_notified === false, r.err ?? '');
await expectNotes('تعديل رقم من المراقب', rid, { req: null, b: { title: 'تم قبول تعديل رقم', body: 'تم قبول طلب تعديل رقم لـ «طاهر»' }, bKind: 'tree_edit' });
rid = await tree({ action: 'edit_phone', targetMemberId: T, newPhone: '+96550000002' }); // رقم T2
r = await decide(P.A, rid, 'approve');
check('ذرّية: رقم مكرر يفشل → لا شيء يُكتب والطلب معلّق', !r.ok && await status(rid) === 'pending' && (await prof(P.T)).phone_number === '+96550000003'
  && (await q(`select count(*)::int n from notifications`))[0].n === 0, r.err ?? '');
await decide(P.A, rid, 'reject');
rid = await tree({ action: 'edit_birth', targetMemberId: T, newBirthDate: '1990-05-01' });
r = await decide(P.A, rid, 'approve');
check('تعديل ميلاد', r.ok && (await one(`select birth_date::text b from profiles where id = $1`, [P.T])).b === '1990-05-01', r.err ?? '');
await expectNotes('تعديل ميلاد', rid, { req: { title: 'تم قبول طلبك', body: 'تم تحديث تاريخ الميلاد إلى: «1990-05-01»' },
  b: { title: 'تم قبول تعديل ميلاد', body: 'تم قبول طلب تعديل ميلاد لـ «طاهر»' }, bKind: 'tree_edit' });
rid = await tree({ action: 'edit_birth', targetMemberId: T, newName: '1991-06-02' });
r = await decide(P.A, rid, 'approve');
check('تعديل ميلاد بالحقل القديم newName', r.ok && (await one(`select birth_date::text b from profiles where id = $1`, [P.T])).b === '1991-06-02', r.err ?? '');
rid = await tree({ action: 'edit_birth', targetMemberId: T, newBirthDate: 'أمس' });
r = await decide(P.A, rid, 'approve'); refused('تاريخ ميلاد غير صالح', r, 'bad_payload');
check('بلا كتابة، معلّق', await status(rid) === 'pending' && (await one(`select birth_date::text b from profiles where id = $1`, [P.T])).b === '1991-06-02');
rid = await tree({ action: 'add_photo', targetMemberId: T, newPhotoUrl: PHOTO(P.M1) });
r = await decide(P.A, rid, 'approve');
check('إضافة صورة من تخزين المشروع', r.ok && (await prof(P.T)).avatar_url === PHOTO(P.M1), r.err ?? '');
await expectNotes('إضافة صورة', rid, { req: { title: 'تم قبول طلبك', body: 'تم اعتماد الصورة لـ «طاهر»' },
  b: { title: 'تم قبول إضافة صورة', body: 'تم قبول طلب إضافة صورة لـ «طاهر»' }, bKind: 'tree_edit' });
rid = await mkreq(P.A, { member: P.T, type: 'tree_edit', details: te({ action: 'add_photo', targetMemberId: P.T, newPhotoUrl: 'https://evil.example/x.jpg' }) });
r = await decide(P.A2, rid, 'approve');
check('رابط خارجي (طلب من الإدارة): يُقبل بلا كتابة كالآيفون', r.ok && (await prof(P.T)).avatar_url === PHOTO(P.M1), r.err ?? '');
await expectNotes('رابط خارجي', rid, { req: { title: 'تم قبول طلبك', body: 'تم قبول طلب تعديل الشجرة' },
  b: { title: 'تم قبول إضافة صورة', body: 'تم قبول طلب إضافة صورة لـ «طاهر»' }, bKind: 'tree_edit' });
rid = await tree({ action: 'delete', targetMemberId: T });
r = await decide(P.MON, rid, 'approve');
check('حذف = إخفاء من الشجرة', r.ok && (await prof(P.T)).is_hidden_from_tree === true, r.err ?? '');
await expectNotes('حذف', rid, { req: null, b: { title: 'تم قبول حذف', body: 'تم قبول طلب حذف لـ «طاهر»' }, bKind: 'tree_edit' });
rid = await tree({ action: 'deceased', targetMemberId: T, deathDate: '2026-10-05' });
r = await decide(P.A, rid, 'approve');
p = await one(`select is_deceased, death_date::text d from profiles where id = $1`, [P.T]);
check('تسجيل وفاة بتاريخ', r.ok && p.is_deceased && p.d === '2026-10-05', r.err ?? JSON.stringify(p));
check('مربّع إعلان الوفاة بالتاريخ', same(r.res.death_announcement, { name: 'طاهر', member_id: P.T, death_date: '2026-10-05', is_female: false }), JSON.stringify(r.res.death_announcement));
await expectNotes('تسجيل وفاة', rid, { req: { title: 'تم قبول طلبك', body: 'تم تأكيد حالة الوفاة لـ «طاهر»' },
  b: { title: 'تم قبول تسجيل وفاة', body: 'تم قبول طلب تسجيل وفاة لـ «طاهر»' }, bKind: 'tree_edit' });
rid = await tree({ action: 'add_death_date', targetMemberId: T, deathDate: ' 2026-10-04 ' });
r = await decide(P.A, rid, 'approve');
check('إضافة تاريخ وفاة (مقصوص) بلا مربّع إعلان', r.ok && (await one(`select death_date::text d from profiles where id = $1`, [P.T])).d === '2026-10-04' && r.res.death_announcement === null, r.err ?? '');
rid = await tree({ action: 'deceased', targetMemberId: T, deathDate: 'غير محدد' });
r = await decide(P.A, rid, 'approve'); refused('تاريخ وفاة غير صالح', r, 'bad_payload');
await decide(P.A, rid, 'reject');
// وفاة أحد الإدارة: الحارس الحالي يسقط دوره (لم يتغيّر شيء)
rid = await tree({ action: 'deceased', targetMemberId: U(P.A2) }, P.M1, P.A2);
r = await decide(P.A, rid, 'approve');
p = await prof(P.A2);
check('وفاة مدير عبر الدالة: trg_zz_deceased_no_admin_role يرجعه عضواً (الحراس تعمل)', r.ok && p.is_deceased && p.role === 'member', r.err ?? JSON.stringify([p.role]));
await db.exec(`update profiles set is_deceased = false, role = 'admin' where id = '${P.A2}'`);
// إضافة (الطلب عن الأب = مقدّم الطلب)
rid = await tree({ action: 'add', parentMemberId: U(P.M1), parentMemberName: 'مزوّر', newMemberName: ' محمد ' }, P.M1, P.M1);
r = await decide(P.A, rid, 'approve');
p = r.ok ? await prof(r.res.new_member_id) : null;
check('إضافة: ملف جديد تحت الأب (مفعّل، رقم مخفي، الاسم + اسم الأب)', !!p && p.father_id === P.M1 && p.first_name === 'محمد'
  && p.full_name === 'محمد حسن صلاح عبدالله' && p.status === 'active' && p.role === 'member' && p.is_phone_hidden === true && p.sort_order === 0, r.err ?? JSON.stringify(p));
await expectNotes('إضافة', rid, { req: { title: 'تم قبول طلبك', body: 'تم إضافة «محمد» تحت «حسن صلاح عبدالله»' },
  b: { title: 'تم قبول إضافة', body: 'تم قبول طلب إضافة لـ «حسن صلاح عبدالله»' }, bKind: 'tree_edit' });
rid = await tree({ action: 'إضافة', parentMemberId: P.M1, newMemberName: 'صالح' }, P.M1, P.M1);
r = await decide(P.A, rid, 'approve');
check('الإجراء القديم «إضافة»', r.ok && r.res.action === 'add' && !!r.res.new_member_id, r.err ?? '');
r = await decide(P.A2, rid, 'approve'); refused('موافقتان على «إضافة» لا تكرّران الابن', r, 'already_handled');
check('ابن واحد فقط باسم صالح', (await q(`select count(*)::int n from profiles where first_name = 'صالح'`))[0].n === 1);
// other (تعديل الملف بعد الحد)
const M1 = U(P.M1);
rid = await tree({ action: 'other', targetMemberId: M1, reason: 'profile_marital', newName: 'true' }, P.M1, P.M1);
r = await decide(P.A, rid, 'approve');
check('طلب آخر: الحالة الاجتماعية', r.ok && (await prof(P.M1)).is_married === true, r.err ?? '');
await expectNotes('الحالة الاجتماعية', rid, { req: { title: 'تم قبول طلبك', body: 'تم اعتماد تعديل الحالة الاجتماعية' },
  b: { title: 'تم قبول طلب آخر', body: 'تم قبول طلب طلب آخر لـ «حسن صلاح عبدالله»' }, bKind: 'tree_edit' });
rid = await tree({ action: 'other', targetMemberId: M1, reason: 'profile_phone_hidden', newName: 'false' }, P.M1, P.M1);
await db.exec(`update profiles set is_phone_hidden = true where id = '${P.M1}'`);
r = await decide(P.A, rid, 'approve');
check('طلب آخر: إظهار الرقم', r.ok && (await prof(P.M1)).is_phone_hidden === false, r.err ?? '');
const bio = [{ id: 'ab5c1f2e-1111-4222-8333-944455556666', year: '2001', title: 'تخرج', details: 'جامعة الكويت', extra: 1 }, { id: 'AB5C1F2E-1111-4222-8333-944455556667', title: 'زواج', details: '' }];
rid = await tree({ action: 'other', targetMemberId: M1, reason: 'profile_bio', newName: JSON.stringify(bio) }, P.M1, P.M1);
r = await decide(P.A, rid, 'approve');
p = await prof(P.M1);
check('طلب آخر: النبذة (المعرّف بحروف كبيرة، بلا مفاتيح زائدة، year الغائب لا يُكتب)', r.ok && same(p.bio_json, [
  { id: 'AB5C1F2E-1111-4222-8333-944455556666', year: '2001', title: 'تخرج', details: 'جامعة الكويت' },
  { id: 'AB5C1F2E-1111-4222-8333-944455556667', title: 'زواج', details: '' }]), JSON.stringify(p.bio_json));
rid = await tree({ action: 'other', targetMemberId: M1, reason: 'profile_bio', newName: '[{"title": 5}]' }, P.M1, P.M1);
r = await decide(P.A, rid, 'approve');
check('نبذة لا يقرؤها الآيفون → [] (كما يكتبها الآيفون)', r.ok && JSON.stringify((await prof(P.M1)).bio_json) === '[]', r.err ?? '');
rid = await mkreq(P.A, { member: P.M2, type: 'tree_edit', details: te({ action: 'other', targetMemberId: P.M2, reason: 'سبب حر' }) });
r = await decide(P.O, rid, 'approve');
await expectNotes('طلب حر', rid, { req: { title: 'تم قبول طلبك', body: 'تم قبول طلبك «علي صلاح»' },
  b: { title: 'تم قبول طلب آخر', body: 'تم قبول طلب طلب آخر لـ «علي صلاح»' }, bKind: 'tree_edit' });
// حمولة لا يقرؤها الآيفون (نص حر / بلا v) — قبول بلا كتابة وبالنص الافتراضي
for (const [label, details] of [['نص حر', 'طلب تعديل قديم'], ['JSON بلا v', JSON.stringify({ action: 'edit_name', targetMemberId: P.M2, newName: 'x' })],
                                ['حقل بنوع خطأ', JSON.stringify({ v: 3, action: 'edit_name', targetMemberId: P.M2, newName: 5 })]]) {
  rid = await mkreq('maint', { member: P.M2, requester: P.M1, type: 'tree_edit', details });
  r = await decide(P.A, rid, 'approve');
  check(`${label}: يُقبل بلا كتابة`, r.ok && (await prof(P.M2)).full_name === 'علي صلاح' && r.res.action === null, r.err ?? '');
  await expectNotes(label, rid, { req: { title: 'تم قبول طلبك', body: 'تم قبول طلب تعديل الشجرة' },
    b: { title: 'تم قبول تعديل', body: 'تم قبول طلب تعديل لـ «علي صلاح»' }, bKind: 'tree_edit' });
}
rid = await mkreq('maint', { member: P.M2, requester: P.M1, type: 'tree_edit', details: JSON.stringify({ v: 3, action: 'edit_name', targetMemberId: 'abc', newName: 'x' }) });
r = await decide(P.A, rid, 'approve'); refused('مستهدف ليس معرّفاً', r, 'bad_payload');
rid = await mkreq('maint', { member: P.M2, requester: P.M1, type: 'tree_edit', details: JSON.stringify({ v: 3, action: 'add', parentMemberId: 'abc', newMemberName: 'x' }) });
r = await decide(P.A, rid, 'approve'); refused('أب ليس معرّفاً', r, 'bad_payload');
// الرفض
rid = await tree({ action: 'edit_phone', targetMemberId: T, newPhone: '+96559999999' });
r = await decide(P.A, rid, 'reject', 'رقم خطأ');
check('رفض تعديل الشجرة: لا كتابة', r.ok && (await prof(P.T)).phone_number === '+96550000003' && await status(rid) === 'rejected', r.err ?? '');
await expectNotes('رفض تعديل رقم', rid, { req: { title: 'لم يتم قبول طلبك', body: 'تم رفض طلب تعديل رقم\n«طاهر»\nالسبب: رقم خطأ', kind: 'request_rejected' },
  b: { title: 'تم رفض تعديل رقم', body: 'تم رفض طلب تعديل رقم لـ «طاهر»' }, bKind: 'tree_edit' });
rid = await mkreq('maint', { member: P.M2, requester: P.M1, type: 'tree_edit', details: 'نص' });
await db.exec(`update profiles set full_name = '' where id = '${P.M2}'`);
r = await decide(P.A, rid, 'reject');
await expectNotes('رفض حمولة غير مقروءة بلا اسم', rid, { req: { title: 'لم يتم قبول طلبك', body: 'تم رفض طلب التعديل', kind: 'request_rejected' },
  b: { title: 'تم رفض التعديل', body: 'تم رفض طلب التعديل' }, bKind: 'tree_edit' });
await db.exec(`update profiles set full_name = 'علي صلاح' where id = '${P.M2}'`);
rid = await tree({ action: 'delete', targetMemberId: T });
r = await decide(P.S, rid, 'approve'); refused('المشرف يقبل تعديل شجرة', r, 'not_allowed');

console.log('\n══════ ٧) اقتراح صورة (النوع القديم) ══════');
const PS = `https://poxyxsgvzwmnmewytsiw.supabase.co/storage/v1/object/public/avatars/photo_suggestion_${P.M2}_1700000000.jpg`;
rid = await mkreq('maint', { member: P.M2, requester: P.M1, type: 'photo_suggestion', nv: PS });
r = await decide(P.MON, rid, 'approve');
p = await prof(P.M2);
check('قبول: الصورة + ?v=<وقت>', r.ok && new RegExp(`^${PS.replace(/[.?]/g, '\\$&')}\\?v=\\d{10}$`).test(p.avatar_url), p?.avatar_url);
await expectNotes('قبول الصورة من المراقب', rid, { req: null, b: null });
rid = await mkreq('maint', { member: P.M2, requester: P.M1, type: 'photo_suggestion', nv: PS + '?a=1' });
r = await decide(P.A, rid, 'approve');
check('رابط فيه ? → &v=', r.ok && /\?a=1&v=\d+$/.test((await prof(P.M2)).avatar_url), (await prof(P.M2)).avatar_url);
await expectNotes('قبول الصورة من المدير', rid, { req: { title: 'تم قبول اقتراحك', body: 'الصورة المقترحة تم قبولها وتحديثها' }, b: null });
rid = await mkreq('maint', { member: P.M2, requester: P.M1, type: 'photo_suggestion', nv: PS });
r = await decide(P.A, rid, 'reject', 'غير واضحة');
check('رفض: ملف الاقتراح للحذف من التطبيق', r.ok && same(r.res.storage_cleanup, { paths: [`photo_suggestion_${P.M2}_1700000000.jpg`], bucket: 'avatars' }), JSON.stringify(r.res.storage_cleanup));
await expectNotes('رفض الصورة', rid, { req: { title: 'لم يتم قبول طلبك', body: 'اقتراح الصورة لم تتم الموافقة عليه\nالسبب: غير واضحة', kind: 'request_rejected' }, b: null });
rid = await mkreq('maint', { member: P.M2, requester: P.M1, type: 'photo_suggestion', nv: `https://poxyxsgvzwmnmewytsiw.supabase.co/storage/v1/object/public/avatars/${P.O}.jpg` });
r = await decide(P.A, rid, 'reject');
check('رفض برابط صورة عضو (ليس اقتراحاً): لا حذف (أ-٣)', r.ok && r.res.storage_cleanup === null, JSON.stringify(r.res.storage_cleanup));
rid = await mkreq('maint', { member: P.M2, requester: P.M1, type: 'photo_suggestion', nv: '' });
r = await decide(P.A, rid, 'approve'); refused('اقتراح بلا رابط', r, 'bad_payload');

console.log('\n══════ ٨) البلاغات ══════');
rid = await mkreq(P.M1, { member: P.M1, type: 'news_report', nv: P.N1, details: 'بلاغ على محتوى خبر' });
r = await decide(P.MON, rid, 'approve'); refused('المراقب على بلاغ', r, 'not_allowed');
r = await decide(P.S, rid, 'approve');
check('المشرف يقبل بلاغ خبر: الخبر يُحذف', r.ok && !(await one(`select id from news where id = $1`, [P.N1])), r.err ?? '');
await expectNotes('قبول البلاغ من المشرف', rid, { req: null, b: null });
rid = await mkreq(P.M1, { member: P.M1, type: 'news_report', nv: P.N2 });
r = await decide(P.A, rid, 'reject');
check('رفض البلاغ: الخبر باقٍ بلا إشعارات', r.ok && !!(await one(`select id from news where id = $1`, [P.N2])) && await status(rid) === 'rejected', r.err ?? '');
await expectNotes('رفض البلاغ', rid, { req: null, b: null });
rid = await mkreq(P.M2, { member: P.M2, type: 'news_report', nv: 'not-uuid' });
r = await decide(P.A, rid, 'approve');
await expectNotes('قبول البلاغ من المدير', rid, { req: { title: 'تمت مراجعة بلاغك', body: 'بلاغك تم مراجعته واتخاذ الإجراء المناسب' }, b: null });
rid = await mkreq(P.S, { member: P.S, type: 'content_report', nv: P.N2, details: '[مشروع] x' }); // من الإدارة: يتجاوز الحارس
r = await decide(P.A, rid, 'approve');
check('قبول بلاغ محتوى لا يحذف خبراً (أ-٣)', r.ok && !!(await one(`select id from news where id = $1`, [P.N2])), r.err ?? '');
rid = await mkreq(P.M1, { member: P.M1, type: 'content_report', details: '[تعليق] x' });
r = await decide(P.S, rid, 'reject');
check('المشرف يرفض بلاغ محتوى', r.ok && await status(rid) === 'rejected', r.err ?? '');
rid = await mkreq(P.S, { member: P.S, type: 'news_report', nv: P.N2 });
r = await decide(P.S, rid, 'approve'); refused('المشرف يقرّر بلاغه هو', r, 'own_request');

console.log('\n══════ ٩) التراجع ══════');
await db.exec(rollback);
check('التراجع يحذف الدالة', (await q(`select count(*)::int n from pg_proc where proname = 'decide_admin_request'`))[0].n === 0);
await db.exec(mig);
check('إعادة التطبيق تعمل', (await q(`select count(*)::int n from pg_proc where proname = 'decide_admin_request' and prosecdef`))[0].n === 1);
console.log(`\nالنتيجة: ${pass} نجح، ${fail} فشل`);
process.exit(fail ? 1 : 0);
