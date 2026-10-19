// تجربة 20261015120000 (مسار الموافقات — طلب المالك ٢٠٢٦-١٠-١٥) على قاعدة محلية معزولة (لا تلمس السيرفر).
// الطلبات تُنشأ كما تنشئها التطبيقات (عضو عبر حارس الإدراج الحي)، والخطوات بدور authenticated + JWT المتصل.
// المفتاح مطفأ = المسار القديم حرفياً؛ شغّال = مختص يوصي ← المدير يعتمد ← المختص ينفّذ (أو تجاوز المدير)،
// والتنفيذ المبكر مرفوض حتى من الكتابة المباشرة (النسخ القديمة) ومن داخل decide_admin_request.
// في الآخر: التراجع يعيد الشكل كما كان، وتُعاد تجربتا decide_admin_request وحارس الإدراج والترحيل مثبّت.
// التشغيل: cd supabase/tests/family_links && node approvals_workflow.test.mjs
import { PGlite } from '@electric-sql/pglite';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
process.on('unhandledRejection', e => { console.log('خطأ:', e.message, e.where ?? '', (e.query ?? '').slice(0, 300)); process.exit(2); });
const HERE = fileURLToPath(new URL('./', import.meta.url));
const REPO = fileURLToPath(new URL('../../', import.meta.url));
const base = readFileSync(new URL('./base.sql', import.meta.url), 'utf8');
const [baseBody, rest] = base.split('-- ─── المشغّلات');
const baseTriggers = rest.slice(rest.indexOf('\n') + 1);
const grab = (src, name) => { const i = src.indexOf(`create or replace function public.${name}(`); return src.slice(i, src.indexOf('$function$;', i) + '$function$;'.length); };
const preFns = ['adopt_tree_profile', 'merge_member_into_tree', 'women_auto_merge_wife']
  .map(n => grab(readFileSync(`${REPO}/rollback/20261001150000_protect_family_links_rollback.sql`, 'utf8'), n)).join('\n\n');
const links = readFileSync(`${REPO}/migrations/20261001150000_protect_family_links.sql`, 'utf8');
const guard = readFileSync(`${REPO}/migrations/20261004200000_admin_requests_insert_guard.sql`, 'utf8');
const decideMig = readFileSync(`${REPO}/migrations/20261007170000_decide_admin_request.sql`, 'utf8');
const MIG = '20261015120000_approvals_workflow';
const mig = readFileSync(`${REPO}/migrations/${MIG}.sql`, 'utf8');
const rollback = readFileSync(`${REPO}/rollback/${MIG}_rollback.sql`, 'utf8');
// ٢٠٢٦-١٠-١٥: المالك يراجع طلبه هو (بديل المختص)
const ownerFix = readFileSync(`${REPO}/migrations/20261015130000_approvals_owner_own_request.sql`, 'utf8');
// ٢٠٢٦-١٠-١٥: «طلب معلومات» منظّم (المختص يختار الناقص: الهاتف/الميلاد/الوفاة/الاسم الكامل)
const INFO = '20261015150000_approvals_info_fields';
const infoMig = readFileSync(`${REPO}/migrations/${INFO}.sql`, 'utf8');
const infoRollback = readFileSync(`${REPO}/rollback/${INFO}_rollback.sql`, 'utf8');

// ─── نسخ الحي (٢٠٢٦-١٠-١٥) لما يلمسه المسار: الجدول وسياساته، الإشعارات ومشغّلاتها، app_settings ───
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
create policy admin_requests_delete_by_scope on public.admin_requests for delete to authenticated
  using (public.can_handle_admin_request(request_type));
create policy require_authenticated_admin_requests on public.admin_requests as restrictive for all
  using (auth.uid() is not null) with check (auth.uid() is not null);
grant usage on schema auth to authenticated, anon;
grant select, insert, update, delete on public.admin_requests to authenticated;

create table public.app_settings (id uuid primary key default gen_random_uuid(),
  news_requires_approval boolean not null default true, updated_at timestamptz not null default now(),
  updated_by uuid, branch_names jsonb not null default '{}'::jsonb);
alter table public.app_settings enable row level security;
create policy "Authenticated users can read app_settings" on public.app_settings for select to authenticated using (true);
create policy "Owner can update app_settings" on public.app_settings for update to authenticated
  using (public.current_user_role() = 'owner') with check (public.current_user_role() = 'owner');
grant select, insert, update, delete on public.app_settings to authenticated, anon;
insert into public.app_settings default values;

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
create or replace function public.skip_client_join_notification() returns trigger language plpgsql
  set search_path to 'public' as $function$
begin
  if new.target_member_id is null and new.kind = 'link_request' and new.request_type = 'join_request' then return null; end if;
  return new;
end; $function$;
create or replace function public.admin_sender_as_administration() returns trigger language plpgsql security definer
  set search_path to 'public' as $function$
begin
  if new.kind in ('news_like', 'news_comment') and new.created_by is not null and new.target_member_id is not null
     and exists (select 1 from public.profiles p where p.id = new.created_by and p.role in ('owner', 'admin', 'monitor', 'supervisor'))
     and exists (select 1 from public.profiles p where p.id = new.target_member_id and p.role in ('member', 'pending')) then
    new.body := case new.kind when 'news_like' then 'الإدارة أعجبت بخبرك' else 'الإدارة علّقت على خبرك' end;
  end if;
  return new;
end; $function$;
create trigger aa_skip_client_join_notification before insert on public.notifications for each row execute function public.skip_client_join_notification();
create trigger trg_a_guard_notification_sender before insert on public.notifications for each row execute function public.guard_notification_sender();
create trigger trg_admin_sender_as_administration before insert on public.notifications for each row execute function public.admin_sender_as_administration();
create trigger trg_fanout_broadcast_notification before insert on public.notifications for each row execute function public.fanout_broadcast_notification();
create trigger trg_notifications_fill_subject before insert on public.notifications for each row execute function public.notifications_fill_subject();

-- الدفع: نفس فحص trigger_push_on_notification الحي (التفضيلات) — يُسجَّل بدل net.http_post
create or replace function public.notification_category(p_kind text, p_target uuid, p_subject uuid) returns text
  language sql immutable set search_path to 'public' as $function$
  select case
    when p_kind in ('admin_broadcast', 'app_update', 'test') then null
    when p_kind = 'news_like' then 'likes'
    when p_kind = 'news_comment' then 'comments'
    when p_kind = 'news_published' then 'news'
    when p_kind like 'admin_edit%' and p_subject is not null and p_subject = p_target then 'profile'
    when p_kind in ('join_approved', 'account_activated', 'role_change', 'request_rejected')
      or p_kind like '%\\\\_approved' or p_kind like '%\\\\_rejected' then 'requests'
    else 'admin_activity'
  end; $function$;
create or replace function public.notification_push_allowed(p_target uuid, p_kind text, p_subject uuid) returns boolean
  language sql stable security definer set search_path to 'public' as $function$
  select case
    when p_target is null then true
    when public.notification_category(p_kind, p_target, p_subject) is null then true
    else coalesce((select (notification_prefs ->> public.notification_category(p_kind, p_target, p_subject)) is distinct from 'false'
                   from public.profiles where id = p_target), true)
  end; $function$;
create table public.push_attempts (target uuid, kind text, title text);
create or replace function public.trigger_push_on_notification() returns trigger language plpgsql security definer
  set search_path to 'public' as $function$
begin
  if pg_trigger_depth() > 1 and coalesce(new.kind, '') in ('admin_broadcast', 'app_update') then return new; end if;
  if not public.notification_push_allowed(new.target_member_id, coalesce(new.kind, ''), new.subject_member_id) then return new; end if;
  insert into public.push_attempts values (new.target_member_id, new.kind, new.title);
  return new;
end; $function$;
create trigger trg_push_on_notification after insert on public.notifications for each row execute function public.trigger_push_on_notification();

-- إشعار طلب الانضمام المحفوظ (الحي — 20261006120000)
create unique index notifications_join_request_recipient_unique on public.notifications (target_member_id, (details->>'join_request_id'))
  where kind = 'link_request' and details->>'join_request_id' is not null;
create or replace function public.notify_admins_on_saved_join_request() returns trigger language plpgsql security definer
  set search_path to 'public' as $function$
declare v_profile_id uuid; v_name text;
begin
  if new.status is distinct from 'pending' or new.request_type not in ('link_request', 'join_request') then return new; end if;
  v_profile_id := coalesce(new.requester_id, new.member_id);
  select coalesce(nullif(trim(full_name), ''), nullif(trim(first_name), ''), 'عضو جديد') into v_name from public.profiles where id = v_profile_id;
  if not found then return new; end if;
  insert into public.notifications (target_member_id, title, body, kind, created_by, is_read, request_id, request_type, subject_member_id, details)
  select p.id, 'طلب انضمام جديد', v_name || ' قدّم طلب انضمام جديد', 'link_request', v_profile_id, false,
    v_profile_id, 'join_request', v_profile_id, jsonb_build_object('join_request_id', new.id)
  from public.profiles p
  where p.role in ('owner', 'admin', 'monitor', 'supervisor') and p.status = 'active' and p.id <> v_profile_id
  on conflict do nothing;
  return new;
end; $function$;
create trigger trg_notify_admins_saved_join_request after insert on public.admin_requests for each row execute function public.notify_admins_on_saved_join_request();
`;

const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const P = { O: id(1), A: id(2), A2: id(3), MON: id(4), S: id(5), FA: id(6), M1: id(10), M2: id(11), PEND: id(14), G: id(17), N1: id(80) };
const NAME = { M1: 'حسن صلاح المحمدعلي', M2: 'علي صلاح', MON: 'علي المراقب', A2: 'خالد المدير' };

let pass = 0, fail = 0;
const check = (l, ok, x = '') => { ok ? pass++ : fail++; console.log(`${ok ? '✅' : '❌'} ${l}${x ? ' — ' + x : ''}`); };

const db = new PGlite();
await db.exec(baseBody); await db.exec(preFns); await db.exec(baseTriggers); await db.exec(links);
await db.exec(live); await db.exec(guard); await db.exec(decideMig);
await db.exec(`
  insert into profiles(id, first_name, full_name, gender, role, status) values ('${P.G}', 'صلاح', 'صلاح الجد', 'male', 'member', 'active');
  insert into women_members(id, first_name, full_name, gender) values ('${P.G}', 'صلاح', 'صلاح الجد', 'male');
  insert into profiles(id, first_name, full_name, gender, role, status) values
    ('${P.O}', 'مالك', 'المالك', 'male', 'owner', 'active'),
    ('${P.A}', 'بدر', 'بدر المدير', 'male', 'admin', 'active'),
    ('${P.A2}', 'خالد', '${NAME.A2}', 'male', 'admin', 'active'),
    ('${P.MON}', 'علي', '${NAME.MON}', 'male', 'monitor', 'active'),
    ('${P.S}', 'سعد', 'سعد المشرف', 'male', 'supervisor', 'active'),
    ('${P.FA}', 'مجمّد', 'مدير مجمّد', 'male', 'admin', 'frozen'),
    ('${P.M1}', 'حسن', '${NAME.M1}', 'male', 'member', 'active'),
    ('${P.M2}', 'علي', '${NAME.M2}', 'male', 'member', 'active'),
    ('${P.PEND}', 'جديد', 'مسجّل معلّق', 'male', 'pending', 'pending');
  update profiles set father_id = '${P.G}' where id in ('${P.M1}', '${P.M2}');
  insert into auth.users(id) values ('${P.O}'), ('${P.A}'), ('${P.A2}'), ('${P.MON}'), ('${P.S}'), ('${P.FA}'),
    ('${P.M1}'), ('${P.M2}'), ('${P.PEND}');
  insert into news(id, content) values ('${P.N1}', 'خبر ١');
  grant select, insert, update on public.profiles to authenticated;`);
const q = async (sql, params = []) => (await db.query(sql, params)).rows;
const one = async (sql, params = []) => (await q(sql, params))[0];

// شكل السيرفر قبل الترحيل (للمقارنة بعد التراجع)
const shape = async () => JSON.stringify(await q(`
  select 'col' k, table_name || '.' || column_name || ':' || data_type || ':' || is_nullable || ':' || coalesce(column_default, '') v
    from information_schema.columns where table_schema = 'public' and table_name in ('admin_requests', 'app_settings', 'notifications')
  union all select 'trg', c.relname || '.' || t.tgname from pg_trigger t join pg_class c on c.oid = t.tgrelid
    where c.relnamespace = 'public'::regnamespace and not t.tgisinternal
  union all select 'fn', p.oid::regprocedure::text from pg_proc p where p.pronamespace = 'public'::regnamespace
  union all select 'tbl', tablename from pg_tables where schemaname = 'public'
  union all select 'con', conrelid::regclass::text || '.' || conname from pg_constraint where connamespace = 'public'::regnamespace
  union all select 'pol', tablename || '.' || policyname from pg_policies where schemaname = 'public'
  order by 1, 2`));
// الشكل مع نصوص الدوال وصلاحياتها ومعاملاتها الافتراضية والقيود والمشغّلات — للتراجع «حرفياً»
const deepShape = async () => JSON.stringify([await shape(),
  await q(`select p.oid::regprocedure::text f, md5(p.prosrc) m, coalesce(p.proacl::text, '') a, p.prosecdef s,
             pg_get_function_arguments(p.oid) args from pg_proc p where p.pronamespace = 'public'::regnamespace order by 1`),
  await q(`select conname, pg_get_constraintdef(oid) d from pg_constraint where connamespace = 'public'::regnamespace order by 1`),
  await q(`select tgname, pg_get_triggerdef(oid) d from pg_trigger where not tgisinternal order by 1`),
  await q(`select c.relname, a.attname, col_description(c.oid, a.attnum) d from pg_attribute a join pg_class c on c.oid = a.attrelid
             where c.relname = 'admin_requests' and a.attnum > 0 and not a.attisdropped order by 1, 2`)]);
const before = await shape();
await db.exec(mig);
await db.exec(ownerFix);
const mid = await deepShape();   // حالة 20261015130000 (الحي قبل «طلب معلومات» منظّم)
await db.exec(infoMig);

// المتصل: uuid · 'maint' (صيانة SQL بلا JWT)
async function as(who, sql, params = []) {
  const claims = who === 'maint' ? '' : JSON.stringify({ sub: who, role: 'authenticated' });
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [claims]);
  if (who !== 'maint') await db.exec('set role authenticated');
  try { return { ok: true, rows: (await db.query(sql, params)).rows }; }
  catch (e) { return { ok: false, err: e.message, hint: e.hint, code: e.code }; }
  finally { if (who !== 'maint') await db.exec('reset role'); await db.query(`select set_config('request.jwt.claims', '', false)`); }
}
async function mkreq(who, r) {
  const res = await as(who, `insert into public.admin_requests (member_id, requester_id, request_type, status, new_value, details)
    values ($1::uuid, $2::uuid, $3, $4, $5, $6) returning id`,
    [r.member, r.requester ?? (who === 'maint' ? r.member : who), r.type, r.status ?? 'pending', r.nv ?? null, r.details ?? null]);
  if (!res.ok) throw new Error(`إنشاء الطلب فشل (${r.type}): ${res.err}`);
  return res.rows[0].id;
}
const clearNotes = () => db.exec('delete from notifications; delete from push_attempts;');
async function decide(who, rid, decision, reason = null) {
  await clearNotes();
  const r = await as(who, `select public.decide_admin_request($1::uuid, $2, $3) as r`, [rid, decision, reason]);
  return r.ok ? { ok: true, res: r.rows[0].r } : r;
}
async function adv(who, rid, action, note = null, fields = null, values = null) {
  await clearNotes();
  const r = await as(who, `select public.advance_admin_request($1::uuid, $2, $3,
      (select array_agg(x) from jsonb_array_elements_text($4::jsonb) x), $5::jsonb) as r`,
    [rid, action, note, fields === null ? null : JSON.stringify(fields), values === null ? null : JSON.stringify(values)]);
  return r.ok ? { ok: true, res: r.rows[0].r } : r;
}
// استدعاء النسخ الحالية (PostgREST بالأسماء الثلاثة فقط)
async function advNamed(who, rid, action, note = null) {
  await clearNotes();
  const r = await as(who, `select public.advance_admin_request(p_request_id => $1::uuid, p_action => $2, p_note => $3) as r`,
    [rid, action, note]);
  return r.ok ? { ok: true, res: r.rows[0].r } : r;
}
async function direct(who, rid, statusTo) {   // كتابة مباشرة كما في النسخ القديمة
  await clearNotes();
  return as(who, `update admin_requests set status = $2 where id = $1 and status = 'pending'`, [rid, statusTo]);
}
const req = async rid => one(`select * from admin_requests where id = $1`, [rid]);
const steps = async rid => q(`select action, actor_id, actor_role, note from admin_request_steps where request_id = $1 order by created_at, action`, [rid]);
const notes = async () => q(`select * from notifications order by target_member_id`);
const nameOf = async pid => (await one(`select full_name from profiles where id = $1`, [pid])).full_name;
const pushes = async () => q(`select * from push_attempts order by target`);
const refused = (label, r, hint) => check(`${label} → ${hint}`, !r.ok && r.hint === hint, r.ok ? 'نجح!' : `${r.hint}: ${r.err}`);
const setSwitch = async (who, on) => as(who, `update app_settings set approvals_workflow = $1 returning approvals_workflow`, [on]);
const sameSet = (a, b) => a.length === b.length && [...a].sort().join() === [...b].sort().join();
// jsonb يرتّب المفاتيح بطوله — نقارن المحتوى لا الترتيب
const sameObj = (a, b) => !!a && !!b && JSON.stringify(Object.entries(a).sort()) === JSON.stringify(Object.entries(b).sort());

// ══════════════════════════════════════════════════════════════════════
console.log('══════ ١) المفتاح مطفأ = المسار القديم حرفياً ══════');
let rid = await mkreq(P.M1, { member: P.M1, type: 'name_change', nv: 'حسن صلاح عبدالله' });
let x = await req(rid);
check('الإدراج: بلا مرحلة ولا خطوات', x.stage === null && x.stage_since === null && (await steps(rid)).length === 0);
let r = await decide(P.MON, rid, 'approve');
x = await req(rid);
check('المراقب يقبل مباشرة (decide_admin_request) كما اليوم', r.ok && x.status === 'approved' && x.stage === null
  && (await one(`select full_name from profiles where id = $1`, [P.M1])).full_name === 'حسن صلاح عبدالله', r.err ?? '');
check('ولا خطوات تُسجَّل', (await steps(rid)).length === 0);
rid = await mkreq(P.M1, { member: P.M1, type: 'phone_change', nv: '+96550000099' });
r = await direct(P.A, rid, 'approved');
check('كتابة مباشرة للحالة (أندرويد/الموقع) تعمل', r.ok && (await req(rid)).status === 'approved', r.err ?? '');
rid = await mkreq(P.M1, { member: P.M1, type: 'name_change', nv: 'اسم' });
r = await direct(P.S, rid, 'rejected');
check('المشرف لا يملك طلب شجرة — سياسة الجدول كما هي (لا تغيير)', r.ok && (await req(rid)).status === 'pending');
r = await adv(P.MON, rid, 'recommend_approve');
refused('خطوة في المسار والمفتاح مطفأ', r, 'workflow_off');
r = await as(P.M1, `insert into admin_requests (member_id, requester_id, request_type, new_value, stage, approved_by)
  values ($1, $1, 'name_change', 'x', 'execute', $2) returning stage, approved_by`, [P.M1, P.O]);
check('عضو يرسل مرحلة مفبركة: تُمسح', r.ok && r.rows[0].stage === null && r.rows[0].approved_by === null, r.err ?? '');
r = await as(P.A, `update admin_requests set stage = 'execute' where id = $1`, [rid]);
refused('تعديل مباشر لأعمدة المسار (حتى والمفتاح مطفأ)', r, 'not_allowed');

console.log('\n══════ ٢) المفتاح: المالك فقط ══════');
r = await setSwitch(P.A, true);
check('المدير لا يشغّله (سياسة المالك)', r.ok && r.rows.length === 0);
r = await setSwitch(P.O, true);
check('المالك يشغّله', r.ok && r.rows[0]?.approvals_workflow === true, r.err ?? '');
r = await as(P.M2, `select approvals_workflow from app_settings`);
check('كل مسجّل يقرأه', r.ok && r.rows[0].approvals_workflow === true);
r = await as(P.M2, `select public.is_workflow_specialist('name_change') a, public.workflow_specialist_role('news_report') b,
  public.workflow_specialist_role('contact_message') c, public.workflow_specialist_role('join_request') d`);
check('workflow_specialist_role: مشرف للبلاغات، لا شيء للتواصل، مراقب للباقي', r.ok && r.rows[0].a === false
  && r.rows[0].b === 'supervisor' && r.rows[0].c === null && r.rows[0].d === 'monitor');

console.log('\n══════ ٣) الإدراج والمفتاح شغّال ══════');
await clearNotes();
const R1 = await mkreq(P.M1, { member: P.M1, type: 'name_change', nv: 'حسن صلاح الجديد' });
x = await req(R1);
let s = await steps(R1);
check('طلب العضو: مرحلة «مراجعة» + وقتها', x.stage === 'review' && x.stage_since !== null && x.status === 'pending');
check('خطوة «submitted» باسم صاحب الطلب', s.length === 1 && s[0].action === 'submitted' && s[0].actor_id === P.M1 && s[0].actor_role === 'member', JSON.stringify(s));
r = await as(P.M1, `insert into admin_requests (member_id, requester_id, request_type, new_value, stage, approved_by, recommendation)
  values ($1, $1, 'name_change', 'x', 'execute', $2, 'approve') returning id, stage, approved_by, recommendation`, [P.M1, P.O]);
check('مرحلة مفبركة عند الإدراج → «مراجعة» وتُمسح البقية', r.ok && r.rows[0].stage === 'review' && r.rows[0].approved_by === null && r.rows[0].recommendation === null, r.err ?? '');
const CM = await mkreq(P.M1, { member: P.M1, type: 'contact_message', nv: 'استفسار', details: 'الرسالة: سؤال' });
check('رسالة تواصل خارج المسار: بلا مرحلة ولا خطوات', (await req(CM)).stage === null && (await steps(CM)).length === 0);
await clearNotes();
const LR = await mkreq(P.PEND, { member: P.PEND, type: 'link_request', details: 'طلب انضمام جديد — لا توجد مطابقات' });
const joinNotes = await q(`select target_member_id from notifications where kind = 'link_request'`);
check('طلب الانضمام: مرحلة «مراجعة» + إشعار الانضمام المحفوظ ما زال لكل إداري نشط (٥)',
  (await req(LR)).stage === 'review' && joinNotes.length === 5, `${joinNotes.length}`);
const bad = await as(P.M1, `insert into admin_requests (member_id, requester_id, request_type, new_value) values ($1, $1, 'join_request', 'x')`, [P.M1]);
check('حارس الإدراج الحي ما زال يعمل (نوع غير مسموح للعضو)', !bad.ok && /admin_request_type_not_allowed/.test(bad.err), bad.err ?? 'قُبل!');

console.log('\n══════ ٤) الصلاحيات والتنفيذ المبكر ══════');
r = await adv(P.M2, R1, 'recommend_approve'); refused('عضو آخر يحرّك طلب غيره', r, 'not_allowed');
r = await adv(P.M1, R1, 'recommend_approve'); refused('صاحب الطلب يوصي لنفسه', r, 'not_allowed');
r = await adv(P.S, R1, 'recommend_approve'); refused('المشرف على طلب شجرة', r, 'not_allowed');
r = await adv(P.FA, R1, 'approve'); refused('مدير مجمّد', r, 'not_allowed');
r = await decide(P.A, R1, 'approve'); refused('المدير ينفّذ وهو «مراجعة» (decide_admin_request)', r, 'approval_needs_manager');
check('…ورسالة عربية', /الطلب يحتاج اعتماد المدير قبل التنفيذ/.test(r.err ?? ''), r.err);
r = await decide(P.MON, R1, 'approve'); refused('المراقب ينفّذ قبل الاعتماد (decide_admin_request)', r, 'approval_needs_manager');
r = await direct(P.A, R1, 'approved'); refused('المدير يكتب الحالة مباشرة (نسخة قديمة)', r, 'approval_needs_manager');
r = await direct(P.MON, R1, 'approved'); refused('المراقب يكتب الحالة مباشرة (نسخة قديمة)', r, 'approval_needs_manager');
x = await req(R1);
check('لا شيء طُبّق: معلّق، «مراجعة»، الاسم كما هو، بلا إشعارات',
  x.status === 'pending' && x.stage === 'review' && (await one(`select full_name from profiles where id = $1`, [P.M1])).full_name === 'حسن صلاح عبدالله'
  && (await notes()).length === 0);
r = await as(P.A, `update admin_requests set stage = 'execute', approved_by = $2 where id = $1`, [R1, P.A]);
refused('المدير يقفز للتنفيذ بتعديل المرحلة مباشرة', r, 'not_allowed');
r = await as(P.MON, `update admin_requests set admin_reply = 'ملاحظة' where id = $1 returning admin_reply`, [R1]);
check('تعديل عمود آخر (الرد) يمر كما اليوم', r.ok && r.rows[0]?.admin_reply === 'ملاحظة', r.err ?? '');
r = await adv(P.MON, R1, 'recommend_reject'); refused('توصية بالرفض بلا سبب', r, 'note_required');
r = await adv(P.MON, R1, 'recommend_reject', '   '); refused('توصية بالرفض بسبب فارغ', r, 'note_required');
r = await adv(P.MON, R1, 'maybe'); refused('إجراء غير معروف', r, 'bad_action');
r = await adv(P.A, R1, 'approve'); refused('المدير يعتمد وهو «مراجعة»', r, 'wrong_stage');

console.log('\n══════ ٥) طلب معلومات ← رد صاحب الطلب ══════');
r = await adv(P.MON, R1, 'request_info'); refused('طلب معلومات بلا نص', r, 'note_required');
r = await adv(P.MON, R1, 'request_info', 'أرفق صورة البطاقة');
x = await req(R1); let n = await notes();
check('المختص يطلب معلومات → «معلومات»', r.ok && r.res.stage === 'info' && x.stage === 'info' && x.info_request === 'أرفق صورة البطاقة', r.err ?? JSON.stringify(r.res));
check('إشعار صاحب الطلب (kind admin) + دفعه', n.length === 1 && n[0].target_member_id === P.M1 && n[0].kind === 'admin'
  && n[0].title === 'الإدارة تحتاج معلومات إضافية' && n[0].body === 'بخصوص طلب تغيير الاسم: أرفق صورة البطاقة'
  && n[0].created_by === P.MON && n[0].details?.type === 'approval_workflow' && n[0].details?.request_id === R1
  && n[0].request_id === null && (await pushes()).length === 1, JSON.stringify(n.map(v => [v.target_member_id, v.title, v.body])));
r = await adv(P.MON, R1, 'recommend_approve'); refused('توصية وهو ينتظر المعلومات', r, 'wrong_stage');
r = await adv(P.M2, R1, 'provide_info', 'رد'); refused('عضو آخر يرد', r, 'not_allowed');
r = await adv(P.MON, R1, 'provide_info', 'رد'); refused('المختص يرد بدل صاحب الطلب', r, 'not_allowed');
r = await adv(P.M1, R1, 'provide_info'); refused('رد فارغ', r, 'note_required');
r = await adv(P.M1, R1, 'provide_info', 'أرسلتها بالبريد');
x = await req(R1); n = await notes();
check('صاحب الطلب يرد → «مراجعة» والسؤال باقٍ', r.ok && x.stage === 'review' && x.info_request === 'أرفق صورة البطاقة', r.err ?? '');
check('إشعار المختص (المراقب) فقط', n.length === 1 && n[0].target_member_id === P.MON && n[0].title === 'وصل ردّ صاحب الطلب'
  && n[0].body === `طلب تغيير الاسم لـ «${await nameOf(P.M1)}»: أرسلتها بالبريد` && n[0].created_by === P.M1, JSON.stringify(n.map(v => [v.target_member_id, v.body])));
r = await adv(P.M1, R1, 'provide_info', 'مرة ثانية'); refused('رد ثانٍ وهو «مراجعة»', r, 'wrong_stage');

console.log('\n══════ ٦) توصية ← إرجاع ← توصية ← اعتماد ← تنفيذ المختص ══════');
r = await adv(P.MON, R1, 'recommend_approve');
x = await req(R1); n = await notes(); const m1name = await nameOf(P.M1);
check('المراقب يوصي بالقبول → «اعتماد»', r.ok && r.res.stage === 'approve' && r.res.request_id === R1 && x.stage === 'approve'
  && x.recommendation === 'approve' && x.recommended_by === P.MON && x.recommended_at !== null, r.err ?? '');
check('إشعار المعتمدين النشطين فقط (المالك + مديران، لا المجمّد)', sameSet(n.map(v => v.target_member_id), [P.O, P.A, P.A2])
  && n.every(v => v.title === 'توصية بانتظار اعتمادك' && v.body === `أوصى المختص بقبول طلب تغيير الاسم لـ «${m1name}»` && v.kind === 'admin')
  && (await pushes()).length === 3, JSON.stringify(n.map(v => [v.target_member_id, v.body])));
r = await adv(P.MON, R1, 'approve'); refused('المختص يعتمد بنفسه', r, 'not_allowed');
r = await decide(P.MON, R1, 'approve'); refused('المختص ينفّذ قبل اعتماد المدير', r, 'approval_needs_manager');
r = await direct(P.MON, R1, 'approved'); refused('المختص يكتب الحالة قبل اعتماد المدير', r, 'approval_needs_manager');
r = await adv(P.A, R1, 'return'); refused('إرجاع بلا ملاحظة', r, 'note_required');
r = await adv(P.A, R1, 'return', 'تأكد من الاسم الثلاثي');
x = await req(R1); n = await notes();
check('المدير يعيد → «مراجعة» مع الملاحظة', r.ok && x.stage === 'review' && x.approval_note === 'تأكد من الاسم الثلاثي', r.err ?? '');
check('إشعار المختص بالإرجاع', n.length === 1 && n[0].target_member_id === P.MON && n[0].title === 'أعاد المدير الطلب للمراجعة');
r = await adv(P.MON, R1, 'recommend_approve', 'تم التأكد');
check('توصية ثانية بملاحظة', r.ok && (await req(R1)).recommendation_note === 'تم التأكد', r.err ?? '');
r = await adv(P.A, R1, 'approve', 'موافق');
x = await req(R1); n = await notes();
check('المدير يعتمد → «تنفيذ»', r.ok && r.res.stage === 'execute' && x.stage === 'execute' && x.approved_by === P.A
  && x.approved_at !== null && x.approval_note === 'موافق' && x.status === 'pending', r.err ?? '');
check('إشعار المختص + صاحب الطلب «تمت الموافقة … يتم التنفيذ»', sameSet(n.map(v => v.target_member_id), [P.MON, P.M1])
  && n.find(v => v.target_member_id === P.M1)?.body === 'تمت الموافقة على طلب تغيير الاسم — يتم التنفيذ'
  && n.find(v => v.target_member_id === P.MON)?.title === 'اعتمد المدير الطلب — جاهز للتنفيذ', JSON.stringify(n.map(v => [v.target_member_id, v.title, v.body])));
r = await decide(P.A2, R1, 'approve'); refused('مدير آخر ينفّذ بعد الاعتماد (يوجد مراقب)', r, 'not_allowed');
r = await direct(P.A2, R1, 'approved'); refused('…ولا بالكتابة المباشرة', r, 'not_allowed');
r = await decide(P.MON, R1, 'approve');
x = await req(R1); n = await notes(); s = await steps(R1);
check('المختص ينفّذ بمسار الموافقة القديم (decide_admin_request) → مغلق', r.ok && x.status === 'approved' && x.stage === null
  && (await one(`select full_name from profiles where id = $1`, [P.M1])).full_name === 'حسن صلاح الجديد', r.err ?? '');
check('أعمدة التوصية والاعتماد باقية للتاريخ', x.recommendation === 'approve' && x.approved_by === P.A && x.approval_note === 'موافق');
check('صاحب الطلب يُشعَر بالتنفيذ (المراقب لا يُشعِره في decide)', n.filter(v => v.target_member_id === P.M1).length === 1
  && n.find(v => v.target_member_id === P.M1).title === 'تم تنفيذ طلبك', JSON.stringify(n.map(v => [v.target_member_id, v.title])));
check('السجل كاملاً بالترتيب', JSON.stringify(s.map(v => v.action)) === JSON.stringify(['submitted', 'request_info', 'provide_info',
  'recommend_approve', 'return', 'recommend_approve', 'approve', 'executed']) && s[7].actor_id === P.MON && s[7].actor_role === 'monitor'
  && s[2].note === 'أرسلتها بالبريد', JSON.stringify(s.map(v => v.action)));
r = await adv(P.A, R1, 'approve'); refused('خطوة على طلب مغلق', r, 'already_handled');
r = await adv(P.A, id(999), 'approve'); refused('طلب غير موجود', r, 'request_not_found');
r = await adv(P.S, CM, 'recommend_approve'); refused('رسالة تواصل في المسار', r, 'wrong_stage');

console.log('\n══════ ٧) الرفض: للمدير في أي مرحلة ══════');
let R2 = await mkreq(P.M1, { member: P.M1, type: 'name_change', nv: 'اسم مرفوض' });
r = await direct(P.MON, R2, 'rejected'); refused('المختص يرفض نهائياً (كتابة مباشرة)', r, 'not_allowed');
r = await decide(P.MON, R2, 'reject', 'لا'); refused('المختص يرفض نهائياً (decide_admin_request)', r, 'not_allowed');
r = await adv(P.MON, R2, 'recommend_reject', 'الاسم غير مطابق للبطاقة');
n = await notes();
check('المختص يوصي بالرفض مع السبب', r.ok && (await req(R2)).recommendation === 'reject'
  && n.length === 3 && n[0].body === `أوصى المختص برفض طلب تغيير الاسم لـ «${await nameOf(P.M1)}»\nالسبب: الاسم غير مطابق للبطاقة`, r.err ?? JSON.stringify(n.map(v => v.body)));
r = await decide(P.A, R2, 'reject', 'الاسم غير مطابق');
x = await req(R2); n = await notes(); s = await steps(R2);
check('المدير يرفض → مغلق بلا مرحلة + خطوة «rejected»', r.ok && x.status === 'rejected' && x.stage === null
  && s.at(-1).action === 'rejected' && s.at(-1).actor_id === P.A, r.err ?? '');
check('صاحب الطلب يُشعَر بالسبب (decide)', n.some(v => v.target_member_id === P.M1 && v.kind === 'request_rejected'
  && v.body === 'طلب تغيير الاسم لم تتم الموافقة عليه\nالسبب: الاسم غير مطابق'));
R2 = await mkreq(P.M1, { member: P.M1, type: 'name_change', nv: 'اسم ٢' });
r = await decide(P.O, R2, 'reject', 'مكرر');
check('المالك يرفض وهو «مراجعة»', r.ok && (await req(R2)).status === 'rejected', r.err ?? '');
R2 = await mkreq(P.M1, { member: P.M1, type: 'name_change', nv: 'اسم ٣' });
await adv(P.MON, R2, 'request_info', 'سؤال');
r = await direct(P.A, R2, 'rejected');
check('المدير يرفض وهو «معلومات» (كتابة مباشرة)', r.ok && (await req(R2)).status === 'rejected' && (await req(R2)).stage === null
  && (await steps(R2)).at(-1).action === 'rejected', r.err ?? '');

console.log('\n══════ ٨) تجاوز المدير: اعتماد وتنفيذ مباشر في مرحلة «اعتماد» ══════');
const R3 = await mkreq(P.M1, { member: P.M1, type: 'name_change', nv: 'حسن صلاح المباشر' });
r = await decide(P.A, R3, 'approve'); refused('المدير ينفّذ مباشرة وهو «مراجعة»', r, 'approval_needs_manager');
await adv(P.MON, R3, 'request_info', 'سؤال');
r = await decide(P.A, R3, 'approve'); refused('المدير ينفّذ مباشرة وهو «معلومات»', r, 'approval_needs_manager');
await adv(P.M1, R3, 'provide_info', 'جواب');
await adv(P.MON, R3, 'recommend_approve');
r = await decide(P.A, R3, 'approve');
x = await req(R3); s = await steps(R3); n = await notes();
check('المدير يعتمد وينفّذ مباشرة (decide_admin_request) → مغلق', r.ok && x.status === 'approved' && x.stage === null
  && x.approved_by === P.A && x.approved_at !== null
  && (await one(`select full_name from profiles where id = $1`, [P.M1])).full_name === 'حسن صلاح المباشر', r.err ?? '');
check('خطوتان: «approve» (اعتماد وتنفيذ مباشر من المدير) ثم «executed»',
  s.at(-2).action === 'approve' && s.at(-2).note === 'اعتماد وتنفيذ مباشر من المدير' && s.at(-1).action === 'executed'
  && s.at(-2).actor_id === P.A && s.at(-1).actor_id === P.A, JSON.stringify(s.slice(-2)));
check('صاحب الطلب يُشعَر مرة واحدة (من decide، لا تكرار)', n.filter(v => v.target_member_id === P.M1).length === 1
  && n.find(v => v.target_member_id === P.M1).title === 'تم تغيير اسمك');
// موافقة الانضمام/الربط في التطبيق (كتابة مباشرة للحالة)
r = await direct(P.A, LR, 'approved'); refused('قبول الانضمام في التطبيق وهو «مراجعة»', r, 'approval_needs_manager');
await adv(P.MON, LR, 'recommend_approve');
r = await direct(P.A, LR, 'approved');
s = await steps(LR);
check('قبول الانضمام في التطبيق وهو «اعتماد» (تجاوز المدير)', r.ok && (await req(LR)).status === 'approved' && (await req(LR)).stage === null
  && JSON.stringify(s.map(v => v.action)) === JSON.stringify(['submitted', 'recommend_approve', 'approve', 'executed']), r.err ?? JSON.stringify(s));
// طلب المدير نفسه
const RA2 = await mkreq(P.A2, { member: P.A2, type: 'name_change', nv: 'خالد الجديد' });
check('طلب من الإدارة بحالة معلّق: يدخل المسار', (await req(RA2)).stage === 'review');
await adv(P.MON, RA2, 'recommend_approve');
r = await adv(P.A2, RA2, 'approve'); refused('المدير يعتمد طلبه هو', r, 'own_request');
r = await decide(P.A2, RA2, 'approve'); refused('المدير ينفّذ طلبه هو', r, 'own_request');
r = await adv(P.A, RA2, 'approve');
check('مدير آخر يعتمده', r.ok && (await req(RA2)).stage === 'execute', r.err ?? '');
const RMON = await mkreq(P.MON, { member: P.MON, type: 'name_change', nv: 'علي المراقب الجديد' });
r = await adv(P.MON, RMON, 'recommend_approve'); refused('المختص يوصي على طلبه هو', r, 'own_request');

// «ربط بالشجرة» (merge_member_into_tree، SECURITY DEFINER) يقبل طلب الانضمام المعلّق = تنفيذه
const PEND2 = id(15), TM = id(16);
await db.exec(`insert into profiles(id, first_name, full_name, gender, role, status) values ('${PEND2}', 'تركي', 'تركي (تسجيل جديد)', 'male', 'pending', 'pending');
  insert into profiles(id, first_name, full_name, gender, role, status, father_id) values ('${TM}', 'تركي', 'تركي صلاح', 'male', 'member', 'active', '${P.G}');
  insert into auth.users(id) values ('${PEND2}');`);
const LR2 = await mkreq(PEND2, { member: PEND2, type: 'link_request', details: 'طلب ربط' });
r = await as(P.MON, `select public.merge_member_into_tree($1, $2) as r`, [PEND2, TM]);
// الدالة تلتقط الخطأ وترجع «فشل الدمج: …» (كما الحي) — كتلة الاستثناء تُرجع كل كتاباتها
check('«ربط بالشجرة» وطلب الانضمام «مراجعة» → «فشل الدمج: الطلب يحتاج اعتماد المدير…» ولا يتغيّر شيء',
  r.ok && r.rows[0].r.success === false && /الطلب يحتاج اعتماد المدير قبل التنفيذ/.test(r.rows[0].r.message)
  && !!(await one(`select id from profiles where id = $1`, [TM])) && (await one(`select status from profiles where id = $1`, [PEND2])).status === 'pending'
  && (await req(LR2)).status === 'pending' && (await req(LR2)).stage === 'review', r.ok ? JSON.stringify(r.rows) : r.err);
await adv(P.MON, LR2, 'recommend_approve'); await adv(P.A, LR2, 'approve');
await clearNotes();
r = await as(P.MON, `select public.merge_member_into_tree($1, $2) as r`, [PEND2, TM]);
check('بعد الاعتماد: المختص يربط → الطلب مغلق «executed» (والتطبيق يُشعِر بالقبول، لا تكرار من السيرفر)',
  r.ok && r.rows[0].r.success === true && (await req(LR2)).status === 'approved' && (await steps(LR2)).at(-1).action === 'executed'
  && (await q(`select 1 from notifications where title = 'تم تنفيذ طلبك'`)).length === 0, r.ok ? JSON.stringify(r.rows[0].r) : r.err);

console.log('\n══════ ٩) البلاغات: المشرف مختص ══════');
const NR = await mkreq(P.M1, { member: P.M1, type: 'news_report', nv: P.N1 });
r = await adv(P.MON, NR, 'recommend_approve'); refused('المراقب على بلاغ', r, 'not_allowed');
r = await adv(P.S, NR, 'recommend_approve');
check('المشرف يوصي', r.ok && (await req(NR)).stage === 'approve', r.err ?? '');
r = await adv(P.O, NR, 'approve');
check('المالك يعتمد', r.ok && (await req(NR)).stage === 'execute', r.err ?? '');
r = await decide(P.S, NR, 'approve');
check('المشرف ينفّذ: الخبر يُحذف والطلب مغلق', r.ok && (await req(NR)).status === 'approved'
  && !(await one(`select id from news where id = $1`, [P.N1])), r.err ?? '');

console.log('\n══════ ١٠) لا مراقب نشط: المالك والمدير مقام المختص ══════');
await db.exec(`update profiles set status = 'frozen' where id = '${P.MON}'`);
const R4 = await mkreq(P.M2, { member: P.M2, type: 'name_change', nv: 'علي صلاح الجديد' });
r = await as(P.A, `select public.is_workflow_specialist('name_change') a, public.is_workflow_specialist('news_report') b`);
check('is_workflow_specialist: المدير مختص للشجرة (لا مراقب)، لا للبلاغات (يوجد مشرف)', r.rows[0].a === true && r.rows[0].b === false);
r = await adv(P.MON, R4, 'recommend_approve'); refused('المراقب المجمّد', r, 'not_allowed');
r = await adv(P.A, R4, 'request_info', 'سؤال');
await adv(P.M2, R4, 'provide_info', 'جواب');
n = await q(`select target_member_id from notifications`);
check('رد صاحب الطلب يصل للمالك والمديرين (بدل المراقب)', r.ok && sameSet(n.map(v => v.target_member_id), [P.O, P.A, P.A2]), JSON.stringify(n));
r = await adv(P.A, R4, 'recommend_approve');
check('المدير يوصي (بديل المختص)', r.ok && (await req(R4)).stage === 'approve', r.err ?? '');
r = await adv(P.A2, R4, 'approve');
n = await notes();
check('مدير آخر يعتمد → «تنفيذ»، والإشعار للبدلاء عدا المعتمد', r.ok && (await req(R4)).stage === 'execute'
  && sameSet(n.filter(v => v.target_member_id !== P.M2).map(v => v.target_member_id), [P.O, P.A]), r.err ?? JSON.stringify(n.map(v => v.target_member_id)));
r = await decide(P.A, R4, 'approve');
check('المدير (بديل المختص) ينفّذ → مغلق', r.ok && (await req(R4)).status === 'approved' && (await steps(R4)).at(-1).action === 'executed', r.err ?? '');
// المالك بديل المختص: يراجع طلبه هو (طلب المالك ٢٠٢٦-١٠-١٥)؛ المدير لا
const RO = await mkreq(P.O, { member: P.O, type: 'name_change', nv: 'المالك الجديد' });
r = await adv(P.O, RO, 'recommend_approve');
check('المالك يوصي على طلبه هو (لا مراقب)', r.ok && (await req(RO)).stage === 'approve', r.err ?? '');
const RA3 = await mkreq(P.A2, { member: P.A2, type: 'name_change', nv: 'مدير جديد' });
r = await adv(P.A2, RA3, 'recommend_approve'); refused('المدير يوصي على طلبه هو', r, 'own_request');
await db.exec(`update profiles set status = 'active' where id = '${P.MON}'`);

console.log('\n══════ ١١) رسائل التواصل والصيانة ══════');
r = await direct(P.S, CM, 'approved');
check('المشرف يعالج رسالة تواصل مباشرة والمفتاح شغّال', r.ok && (await req(CM)).status === 'approved' && (await steps(CM)).length === 0, r.err ?? '');
const R5 = await mkreq(P.M1, { member: P.M1, type: 'name_change', nv: 'صيانة' });
r = await as('maint', `update admin_requests set status = 'approved' where id = $1`, [R5]);
x = await req(R5); s = await steps(R5);
// خطوتا «submitted» و«executed» قد تتساويان في الوقت هنا (نفس اللحظة في القاعدة المعزولة) — نتحقق من وجود «executed»
check('صيانة SQL (بلا مستخدم) تغلق بلا فحص وتنظّف المرحلة', r.ok && x.status === 'approved' && x.stage === null && s.some(v => v.action === 'executed'), r.err ?? '');
const R6 = await mkreq(P.M1, { member: P.M1, type: 'name_change', nv: 'صيانة ٢' });
r = await as('maint', `update admin_requests set stage = 'approve' where id = $1`, [R6]);
check('صيانة SQL تعدّل المرحلة', r.ok && (await req(R6)).stage === 'approve', r.err ?? '');

console.log('\n══════ ١٢) سجل الخطوات: القراءة والكتابة ══════');
r = await as(P.M1, `select count(*)::int n from admin_request_steps where request_id = $1`, [R1]);
check('صاحب الطلب يقرأ خطوات طلبه', r.ok && r.rows[0].n === 8, JSON.stringify(r.rows ?? r.err));
r = await as(P.M2, `select count(*)::int n from admin_request_steps where request_id = $1`, [R1]);
check('عضو آخر لا يراها', r.ok && r.rows[0].n === 0);
r = await as(P.S, `select count(*)::int n from admin_request_steps where request_id = $1`, [R1]);
check('الإدارة تراها', r.ok && r.rows[0].n === 8);
r = await as(P.M1, `insert into admin_request_steps (request_id, action) values ($1, 'approve')`, [R6]);
check('لا كتابة مباشرة (حتى للمالك)', !r.ok && /permission denied/.test(r.err), r.err ?? 'كُتب!');
r = await as(P.O, `delete from admin_request_steps where request_id = $1`, [R1]);
check('ولا حذف', !r.ok && /permission denied/.test(r.err), r.err ?? 'حُذف!');

console.log('\n══════ ١٢ب) «طلب معلومات» منظّم: المختص يختار الناقص ══════');
const L = '\u2066', R = '\u2069';   // عزل اتجاه الرقم/التاريخ في الملخّص
r = await as(P.M2, `select count(*)::int n from pg_proc where proname = 'advance_admin_request'`);
check('دالة واحدة باسم advance_admin_request (مرشّح واحد لـ PostgREST)', r.ok && r.rows[0].n === 1, JSON.stringify(r.rows ?? r.err));
r = await as('maint', `select has_function_privilege('authenticated', 'public.advance_admin_request(uuid,text,text,text[],jsonb)', 'execute') a,
  has_function_privilege('anon', 'public.advance_admin_request(uuid,text,text,text[],jsonb)', 'execute') b,
  has_function_privilege('authenticated', 'public.approvals_info_field_label(text)', 'execute') c`);
check('الصلاحيات: authenticated تنفّذ، anon لا، ودالة الأسماء داخلية', r.ok && r.rows[0].a === true && r.rows[0].b === false && r.rows[0].c === false, JSON.stringify(r.rows ?? r.err));
const RI = await mkreq(P.M1, { member: P.M1, type: 'name_change', nv: 'حسن بالحقول' });
r = await as(P.M1, `insert into admin_requests (member_id, requester_id, request_type, new_value, info_fields, info_reply)
  values ($1, $1, 'name_change', 'x', '{phone}', '{"phone":"1"}') returning info_fields, info_reply`, [P.M1]);
check('عضو يرسل حقولاً/رداً مفبركاً عند الإدراج: يُمسح', r.ok && r.rows[0].info_fields === null && r.rows[0].info_reply === null, r.err ?? JSON.stringify(r.rows));
r = await adv(P.MON, RI, 'request_info', null, ['phone', 'iban']); refused('حقل غير معروف', r, 'bad_action');
r = await adv(P.MON, RI, 'request_info', null, ['text']); refused('«توضيح مكتوب» وحده بلا سؤال', r, 'note_required');
r = await adv(P.MON, RI, 'request_info', null, []); refused('قائمة فارغة بلا سؤال', r, 'note_required');
r = await adv(P.MON, RI, 'request_info', null, [' PHONE ', 'phone', 'birth_date', '']);
x = await req(RI); n = await notes(); s = await steps(RI);
check('طلب معلومات بالحقول بلا ملاحظة → «معلومات»، الحقول منظّفة بلا تكرار', r.ok && x.stage === 'info'
  && JSON.stringify(x.info_fields) === JSON.stringify(['phone', 'birth_date']) && x.info_request === null && x.info_reply === null, r.err ?? JSON.stringify(x.info_fields));
check('إشعار صاحب الطلب يسمّي المطلوب بالعربي', n.length === 1 && n[0].target_member_id === P.M1
  && n[0].body === 'بخصوص طلب تغيير الاسم — المطلوب: رقم الهاتف، تاريخ الميلاد', JSON.stringify(n.map(v => v.body)));
check('ملاحظة الخطوة: «المطلوب: …»', s.at(-1).action === 'request_info' && s.at(-1).note === 'المطلوب: رقم الهاتف، تاريخ الميلاد', JSON.stringify(s.at(-1)));
r = await as(P.A, `update admin_requests set info_fields = '{full_name}' where id = $1`, [RI]);
refused('تعديل الحقول المطلوبة مباشرة (حتى المدير)', r, 'not_allowed');
r = await as(P.A, `update admin_requests set info_reply = '{"phone":"+96550000000"}' where id = $1`, [RI]);
refused('كتابة رد مباشرة', r, 'not_allowed');
r = await adv(P.M1, RI, 'provide_info', 'رقمي ٥٠٠٠١٢٣٤'); refused('رد بنص فقط (نسخة قديمة) وطُلبت حقول', r, 'note_required');
check('…ورسالة تسمّي الناقص', /أدخل رقم الهاتف/.test(r.err ?? ''), r.err);
r = await adv(P.M1, RI, 'provide_info', null, null, { phone: '+96550001234' }); refused('تاريخ الميلاد ناقص', r, 'note_required');
check('…«أدخل تاريخ الميلاد»', /أدخل تاريخ الميلاد/.test(r.err ?? ''), r.err);
r = await adv(P.M1, RI, 'provide_info', null, null, { phone: '12345', birth_date: '1990-03-15' }); refused('رقم قصير', r, 'note_required');
check('…«رقم الهاتف غير صحيح»', /رقم الهاتف غير صحيح/.test(r.err ?? ''), r.err);
r = await adv(P.M1, RI, 'provide_info', null, null, { phone: '+96550001234', birth_date: '15/03/1990' }); refused('تاريخ بصيغة أخرى', r, 'note_required');
check('…«تاريخ الميلاد غير صحيح»', /تاريخ الميلاد غير صحيح/.test(r.err ?? ''), r.err);
r = await adv(P.M1, RI, 'provide_info', null, null, { phone: '+96550001234', birth_date: '1990-02-30' }); refused('تاريخ غير موجود (٣٠ فبراير)', r, 'note_required');
r = await adv(P.M1, RI, 'provide_info', null, null, { phone: '+96550001234', birth_date: '2999-01-01' }); refused('تاريخ في المستقبل', r, 'note_required');
check('…«لا يكون في المستقبل»', /لا يكون في المستقبل/.test(r.err ?? ''), r.err);
r = await adv(P.M1, RI, 'provide_info', null, null, { phone: '', birth_date: '1990-03-15' }); refused('هاتف فارغ', r, 'note_required');
check('لا شيء تغيّر بعد الرفض: «معلومات» بلا رد', (await req(RI)).stage === 'info' && (await req(RI)).info_reply === null);
r = await adv(P.M1, RI, 'provide_info', 'ملخص التطبيق', null,
  { phone: '+٩٦٥ ٥٠٠٠-١٢٣٤', birth_date: '1990-03-15', text: '  هذا رقمي الجديد  ', iban: 'KW00', full_name: 'مفبرك' });
x = await req(RI); n = await notes(); s = await steps(RI);
check('رد صالح → «مراجعة» والرد المنظّم محفوظ (المطلوب + النص فقط، الأرقام العربية تُطبَّع)', r.ok && x.stage === 'review'
  && sameObj(x.info_reply, { phone: '+96550001234', birth_date: '1990-03-15', text: 'هذا رقمي الجديد' })
  && JSON.stringify(x.info_fields) === JSON.stringify(['phone', 'birth_date']), r.err ?? JSON.stringify(x.info_reply));
check('ملاحظة الخطوة ملخّص مقروء من السيرفر', s.at(-1).action === 'provide_info'
  && s.at(-1).note === `رقم الهاتف: ${L}+96550001234${R}\nتاريخ الميلاد: ${L}1990-03-15${R}\nهذا رقمي الجديد`, JSON.stringify(s.at(-1).note));
check('إشعار المختص بالملخّص', n.length === 1 && n[0].target_member_id === P.MON && n[0].title === 'وصل ردّ صاحب الطلب'
  && n[0].body === `طلب تغيير الاسم لـ «${await nameOf(P.M1)}»:\nرقم الهاتف: ${L}+96550001234${R}\nتاريخ الميلاد: ${L}1990-03-15${R}\nهذا رقمي الجديد`, JSON.stringify(n.map(v => v.body)));
r = await adv(P.MON, RI, 'request_info', 'للتأكد من البطاقة', ['full_name', 'death_date']);
x = await req(RI); n = await notes();
check('سؤال ثانٍ: حقول جديدة والرد السابق يُمسح (يبقى في السجل)', r.ok && x.stage === 'info' && x.info_reply === null
  && JSON.stringify(x.info_fields) === JSON.stringify(['full_name', 'death_date']) && x.info_request === 'للتأكد من البطاقة', r.err ?? '');
check('…والإشعار: المطلوب + الملاحظة', n[0]?.body === 'بخصوص طلب تغيير الاسم — المطلوب: الاسم الكامل، تاريخ الوفاة\nللتأكد من البطاقة', JSON.stringify(n.map(v => v.body)));
r = await adv(P.M1, RI, 'provide_info', null, null, { full_name: 'حسن', death_date: '2020-01-01' }); refused('اسم من كلمة واحدة', r, 'note_required');
check('…«اكتب الاسم الكامل»', /اكتب الاسم الكامل/.test(r.err ?? ''), r.err);
r = await adv(P.M1, RI, 'provide_info', null, null, { full_name: '  حسن   صلاح  ', death_date: '2020-01-01' });
x = await req(RI);
check('اسم وتاريخ وفاة صالحان (المسافات تُطبَّع)', r.ok && sameObj(x.info_reply, { full_name: 'حسن صلاح', death_date: '2020-01-01' })
  && (await steps(RI)).at(-1).note === `الاسم الكامل: حسن صلاح\nتاريخ الوفاة: ${L}2020-01-01${R}`, r.err ?? JSON.stringify(x.info_reply));
r = await adv(P.MON, RI, 'recommend_approve', null, ['phone'], { phone: 'x' });
check('حقول/قيم مع إجراء آخر: تُتجاهل', r.ok && (await req(RI)).stage === 'approve'
  && JSON.stringify((await req(RI)).info_fields) === JSON.stringify(['full_name', 'death_date']), r.err ?? '');
r = await decide(P.A, RI, 'reject', 'لا');
x = await req(RI);
check('الإغلاق لا يمسح الحقول ولا الرد', r.ok && x.status === 'rejected' && x.stage === null
  && JSON.stringify(x.info_fields) === JSON.stringify(['full_name', 'death_date']) && x.info_reply?.full_name === 'حسن صلاح', r.err ?? '');
const RT = await mkreq(P.M1, { member: P.M1, type: 'name_change', nv: 'نص مطلوب' });
r = await adv(P.MON, RT, 'request_info', 'لماذا تغيّر الاسم؟', ['text']);
check('«توضيح مكتوب» مع سؤال', r.ok && (await req(RT)).stage === 'info', r.err ?? '');
r = await adv(P.M1, RT, 'provide_info', 'نص في الملاحظة فقط'); refused('النص مطلوب في القيم', r, 'note_required');
r = await adv(P.M1, RT, 'provide_info', null, null, { text: 'تصحيح خطأ إملائي' });
check('رد بالنص → الخطوة = النص', r.ok && (await steps(RT)).at(-1).note === 'تصحيح خطأ إملائي'
  && (await req(RT)).info_reply?.text === 'تصحيح خطأ إملائي', r.err ?? '');
// النسخ الحالية: الاستدعاء بالأسماء الثلاثة كما يرسله PostgREST
const RN = await mkreq(P.M1, { member: P.M1, type: 'name_change', nv: 'استدعاء قديم' });
r = await advNamed(P.MON, RN, 'request_info', 'سؤال قديم');
x = await req(RN);
check('الاستدعاء القديم بالأسماء (p_request_id, p_action, p_note) يعمل', r.ok && x.stage === 'info' && x.info_request === 'سؤال قديم'
  && x.info_fields === null && (await notes())[0]?.body === 'بخصوص طلب تغيير الاسم: سؤال قديم', r.err ?? '');
r = await advNamed(P.M1, RN, 'provide_info', 'جواب قديم');
check('…والرد القديم بنص فقط (بلا حقول مطلوبة) كما كان', r.ok && (await req(RN)).stage === 'review' && (await req(RN)).info_reply === null
  && (await steps(RN)).at(-1).note === 'جواب قديم', r.err ?? '');
r = await advNamed(P.M1, RN, 'provide_info'); refused('الاستدعاء القديم بلا ملاحظة', r, 'wrong_stage');

console.log('\n══════ ١٣) إطفاء المفتاح وسط الطريق ══════');
const R7 = await mkreq(P.M1, { member: P.M1, type: 'name_change', nv: 'حسن بعد الإطفاء' });
await adv(P.MON, R7, 'recommend_approve');
const R8 = await mkreq(P.M1, { member: P.M1, type: 'phone_change', nv: '+96550000088' });
r = await setSwitch(P.O, false);
check('المالك يطفئه', r.ok && r.rows[0].approvals_workflow === false);
r = await adv(P.A, R7, 'approve'); refused('خطوة بعد الإطفاء', r, 'workflow_off');
r = await decide(P.MON, R7, 'approve');
x = await req(R7);
check('المعلّق وسط المسار يُعالج بالطريقة القديمة (المراقب يقبل مباشرة)', r.ok && x.status === 'approved' && x.stage === null
  && (await steps(R7)).at(-1).action === 'executed', r.err ?? '');
r = await direct(P.A, R8, 'approved');
check('كتابة مباشرة لطلب كان «مراجعة»', r.ok && (await req(R8)).status === 'approved' && (await req(R8)).stage === null, r.err ?? '');
const R9 = await mkreq(P.M1, { member: P.M1, type: 'name_change', nv: 'جديد بعد الإطفاء' });
check('طلب جديد بعد الإطفاء: بلا مرحلة ولا خطوات', (await req(R9)).stage === null && (await steps(R9)).length === 0);

console.log('\n══════ ١٤) التراجع ══════');
await db.exec(infoRollback);
const afterInfo = await deepShape();
check(`تراجع ${INFO} يعيد حالة 20261015130000 حرفياً (نصوص الدوال، الصلاحيات، المعاملات، القيود، المشغّلات)`, afterInfo === mid,
  afterInfo === mid ? '' : 'مختلف');
r = await advNamed(P.MON, R9, 'request_info', 'سؤال');
refused('بعد التراجع: الدالة بثلاث معاملات تُستدعى بالأسماء (والمفتاح مطفأ)', r, 'workflow_off');
await db.exec(rollback);
const after = await shape();
check('التراجع يعيد الشكل كما قبل الترحيل حرفياً (أعمدة، مشغّلات، دوال، جداول، قيود، سياسات)', after === before,
  after === before ? '' : before.length + ' ≠ ' + after.length);
R2 = await mkreq(P.M1, { member: P.M1, type: 'name_change', nv: 'بعد التراجع' });
r = await direct(P.A, R2, 'approved');
check('بعد التراجع: الكتابة المباشرة كما كانت', r.ok && (await req(R2)).status === 'approved', r.err ?? '');
await db.exec(mig); await db.exec(ownerFix); await db.exec(infoMig);
check('إعادة التطبيق بعد التراجع تعمل (الثلاثة بالترتيب)', (await q(`select count(*)::int n from pg_proc where proname = 'advance_admin_request' and prosecdef`))[0].n === 1
  && (await q(`select pg_get_function_arguments(oid) a from pg_proc where proname = 'advance_admin_request'`))[0].a.includes('p_values jsonb'));
await db.exec(rollback);
check('تراجع 20261015120000 وحده فوق الثلاثة يعيد الشكل كما قبل المسار', (await shape()) === before);
await db.exec(mig);
await db.close();

console.log('\n══════ ١٥) التجارب القائمة والترحيل مثبّت ══════');
const settings = on => `create table if not exists public.app_settings (id uuid primary key default gen_random_uuid(),
  news_requires_approval boolean not null default true); insert into public.app_settings default values;
  ${mig}
  ${ownerFix}
  ${infoMig}
  update public.app_settings set approvals_workflow = ${on};`;
function replay(file, anchor, on, label) {
  const src = readFileSync(HERE + file, 'utf8');
  if (!src.includes(anchor)) { check(`${label}: نقطة الحقن موجودة`, false, anchor); return; }
  const tmp = `${HERE}.wf_replay_${file}`;
  writeFileSync(tmp, src.replace(anchor, () => `${anchor}\nawait db.exec(${JSON.stringify(settings(on))});`));
  try {
    const run = spawnSync(process.execPath, [tmp], { cwd: HERE, encoding: 'utf8' });
    const summary = (run.stdout.match(/النتيجة: \d+ نجح، \d+ فشل/) ?? [''])[0];
    const failed = run.stdout.split('\n').filter(l => l.startsWith('❌')).slice(0, 5).join(' | ');
    check(label, run.status === 0, summary + (failed ? ' ' + failed : '') + (run.status ? ' ' + run.stderr.slice(-600) : ''));
  } finally { unlinkSync(tmp); }
}
replay('decide_admin_request.test.mjs', 'await db.exec(live); await db.exec(guard); await db.exec(mig);', false,
  'decide_admin_request.test.mjs كاملة والترحيلات الثلاثة مثبّتة (المفتاح مطفأ)');
replay('admin_requests_guard.test.mjs', 'if (withGuard) await db.exec(guard);', false,
  'admin_requests_guard.test.mjs كاملة والترحيلات الثلاثة مثبّتة (المفتاح مطفأ)');
replay('admin_requests_guard.test.mjs', 'if (withGuard) await db.exec(guard);', true,
  'admin_requests_guard.test.mjs كاملة والمفتاح شغّال (الإدراج لا يتأثر)');

console.log(`\nالنتيجة: ${pass} نجح، ${fail} فشل`);
process.exit(fail ? 1 : 0);
