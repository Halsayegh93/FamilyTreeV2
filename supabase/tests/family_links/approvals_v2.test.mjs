// تجربة 20261016120000 (مسار الموافقات ٢ — طلب المالك ٢٠٢٦-١٠-١٦) على قاعدة محلية معزولة (لا تلمس السيرفر).
// فوق مسار الموافقات الحي (20261015120000 + 130000 + 150000 + 170000): الأولوية والمستعجل، المسار السريع،
// الاستلام والترك وأخذ المالك، فرض الاستلام في التوصية والتنفيذ والاعتماد، إعادة الاستلام لمن أوصى، المهلة
// والتصعيد (approvals_sla_tick) ومهمة pg_cron، قوالب الردود، الملاحظات الداخلية، تقرير الأداء، الصلاحيات.
// في الآخر: التراجع يعيد حالة 20261015170000 الحية حرفياً (نصوص الدوال = md5 الحي)، وتُعاد تجربة المسار
// كاملة وتجربتا decide_admin_request وحارس الإدراج والترحيل مثبّت (المفتاح مطفأ = المسار القديم حرفياً).
// التشغيل: cd supabase/tests/family_links && node approvals_v2.test.mjs
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
const wfMig = readFileSync(`${REPO}/migrations/20261015120000_approvals_workflow.sql`, 'utf8');
const ownerFix = readFileSync(`${REPO}/migrations/20261015130000_approvals_owner_own_request.sql`, 'utf8');
const infoMig = readFileSync(`${REPO}/migrations/20261015150000_approvals_info_fields.sql`, 'utf8');
const delFix = readFileSync(`${REPO}/migrations/20261015170000_profiles_delete_guard_fix.sql`, 'utf8');
const MIG = '20261016120000_approvals_v2';
const v2 = readFileSync(`${REPO}/migrations/${MIG}.sql`, 'utf8');
const v2rb = readFileSync(`${REPO}/rollback/${MIG}_rollback.sql`, 'utf8');

// md5(prosrc) للدوال الأربع كما في السيرفر الحي ٢٠٢٦-١٠-١٦ (قبل هذا الترحيل) — التراجع يعيدها حرفياً
const LIVE_MD5 = {
  advance_admin_request: '027e6f50c2a0c0603f7381d79714f6b4',
  set_admin_request_stage: '986eb674782f586027a524fea39074a5',
  guard_admin_request_workflow: 'b86ba007b9403a94f4c2b3dfa31b89e2',
  log_admin_request_submitted: '44c6a0063f86f3c693e6894b73edacd8',
};

// pg_cron كما في الحي (1.6.4): cron.job و cron.schedule (بالاسم نفسه يحدّث) و cron.unschedule (يرفض المجهول)
const CRON = `
create schema if not exists cron;
create table if not exists cron.job (jobid bigserial primary key, schedule text not null, command text not null,
  nodename text default 'localhost', nodeport integer default 5432, database text default current_database(),
  username text default current_user, active boolean default true, jobname text unique);
create or replace function cron.schedule(job_name text, schedule text, command text) returns bigint language plpgsql as $c$
declare j bigint;
begin
  insert into cron.job (jobname, schedule, command) values (job_name, schedule, command)
  on conflict (jobname) do update set schedule = excluded.schedule, command = excluded.command returning jobid into j;
  return j;
end $c$;
create or replace function cron.unschedule(job_name text) returns boolean language plpgsql as $c$
begin
  delete from cron.job where jobname = job_name;
  if not found then raise exception 'could not find valid entry for job ''%''', job_name; end if;
  return true;
end $c$;`;

// ─── نسخ الحي (٢٠٢٦-١٠-١٥) لما يلمسه المسار — نفس نسخة approvals_workflow.test.mjs ───
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
const P = { O: id(1), A: id(2), A2: id(3), MON: id(4), S: id(5), FA: id(6), MON2: id(7),
  M1: id(10), M2: id(11), M3: id(12), PEND: id(14), G: id(17), N1: id(80) };

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
    ('${P.A2}', 'خالد', 'خالد المدير', 'male', 'admin', 'active'),
    ('${P.MON}', 'علي', 'علي المراقب', 'male', 'monitor', 'active'),
    ('${P.MON2}', 'فهد', 'فهد المراقب', 'male', 'monitor', 'active'),
    ('${P.S}', 'سعد', 'سعد المشرف', 'male', 'supervisor', 'active'),
    ('${P.FA}', 'مجمّد', 'مدير مجمّد', 'male', 'admin', 'frozen'),
    ('${P.M1}', 'حسن', 'حسن صلاح المحمدعلي', 'male', 'member', 'active'),
    ('${P.M2}', 'عمر', 'عمر صلاح', 'male', 'member', 'active'),
    ('${P.M3}', 'سالم', 'سالم صلاح', 'male', 'member', 'active'),
    ('${P.PEND}', 'جديد', 'مسجّل معلّق', 'male', 'pending', 'pending');
  update profiles set father_id = '${P.G}' where id in ('${P.M1}', '${P.M2}', '${P.M3}');
  insert into auth.users(id) values ('${P.O}'), ('${P.A}'), ('${P.A2}'), ('${P.MON}'), ('${P.MON2}'), ('${P.S}'), ('${P.FA}'),
    ('${P.M1}'), ('${P.M2}'), ('${P.M3}'), ('${P.PEND}');
  insert into news(id, content) values ('${P.N1}', 'خبر ١');
  grant select, insert, update on public.profiles to authenticated;`);
await db.exec(CRON);
// الحي اليوم: المسار + استثناء المالك + «طلب معلومات» منظّم + إصلاح حارس الحذف
await db.exec(wfMig); await db.exec(ownerFix); await db.exec(infoMig); await db.exec(delFix);

const q = async (sql, params = []) => (await db.query(sql, params)).rows;
const one = async (sql, params = []) => (await q(sql, params))[0];

// الشكل الكامل: أعمدة كل الجداول، صلاحيات الجداول، الدوال (نص، صلاحيات، معاملات)، القيود، المشغّلات، السياسات،
// الفهارس، التعليقات، ومهام pg_cron — للتراجع «حرفياً»
const deepShape = async () => JSON.stringify([
  await q(`select table_name, column_name, data_type, is_nullable, coalesce(column_default, '') d
             from information_schema.columns where table_schema = 'public' order by 1, 2`),
  await q(`select c.relname, coalesce(c.relacl::text, '') acl, c.relrowsecurity rls from pg_class c
             where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v') order by 1`),
  await q(`select p.oid::regprocedure::text f, md5(p.prosrc) m, coalesce(p.proacl::text, '') a, p.prosecdef s, p.provolatile v,
             coalesce(p.proconfig::text, '') cfg, pg_get_function_arguments(p.oid) args, pg_get_function_result(p.oid) res
             from pg_proc p where p.pronamespace = 'public'::regnamespace order by 1`),
  await q(`select conrelid::regclass::text t, conname, pg_get_constraintdef(oid) d from pg_constraint
             where connamespace = 'public'::regnamespace order by 1, 2`),
  await q(`select tgrelid::regclass::text t, tgname, pg_get_triggerdef(oid) d from pg_trigger where not tgisinternal order by 1, 2`),
  await q(`select tablename, policyname, cmd, roles::text r, coalesce(qual, '') qq, coalesce(with_check, '') w, permissive
             from pg_policies where schemaname = 'public' order by 1, 2`),
  await q(`select indexname, indexdef from pg_indexes where schemaname = 'public' order by 1`),
  await q(`select c.relname, a.attname, coalesce(col_description(c.oid, a.attnum), '') d from pg_attribute a
             join pg_class c on c.oid = a.attrelid where c.relnamespace = 'public'::regnamespace and c.relkind = 'r'
             and a.attnum > 0 and not a.attisdropped order by 1, 2`),
  await q(`select c.relname, coalesce(obj_description(c.oid, 'pg_class'), '') d from pg_class c
             where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' order by 1`),
  await q(`select jobname, schedule, command from cron.job order by 1`)]);
const liveMd5 = async () => Object.fromEntries((await q(`select proname, md5(prosrc) m from pg_proc
  where pronamespace = 'public'::regnamespace and proname = any($1)`, [Object.keys(LIVE_MD5)])).map(r => [r.proname, r.m]));
const sameMd5 = m => Object.entries(LIVE_MD5).every(([k, v]) => m[k] === v);

console.log('══════ ٠) التراجع على الحي قبل الترحيل = نصوص الحي حرفياً ══════');
await db.exec(v2rb);   // يعمل على قاعدة لم يُطبَّق عليها الترحيل (كل حذف مشروط) ويكتب نصوص الدوال الحية
let m5 = await liveMd5();
check('نصوص الدوال الأربع في ملف التراجع = md5 الحي', sameMd5(m5), JSON.stringify(m5));
const before = await deepShape();
await db.exec(v2);
const once = await deepShape();
await db.exec(v2);
check('الترحيل يُعاد تطبيقه بلا تغيير (مهمة واحدة، قوالب بلا تكرار)', (await deepShape()) === once
  && (await one(`select count(*)::int n from cron.job where jobname = 'approvals-sla'`)).n === 1
  && (await one(`select count(*)::int n from approval_templates`)).n === 10);

// المتصل: uuid · 'maint' (صيانة SQL بلا JWT) · 'anon'
async function as(who, sql, params = []) {
  const claims = who === 'maint' ? '' : JSON.stringify(who === 'anon' ? { role: 'anon' } : { sub: who, role: 'authenticated' });
  const role = who === 'maint' ? null : who === 'anon' ? 'anon' : 'authenticated';
  await db.query(`select set_config('request.jwt.claims', $1, false)`, [claims]);
  if (role) await db.exec(`set role ${role}`);
  try { return { ok: true, rows: (await db.query(sql, params)).rows }; }
  catch (e) { return { ok: false, err: e.message, hint: e.hint, code: e.code }; }
  finally { if (role) await db.exec('reset role'); await db.query(`select set_config('request.jwt.claims', '', false)`); }
}
async function mkreq(who, r) {
  const res = await as(who, `insert into public.admin_requests (member_id, requester_id, request_type, status, new_value, details)
    values ($1::uuid, $2::uuid, $3, $4, $5, $6) returning id`,
    [r.member, r.requester ?? (who === 'maint' ? r.member : who), r.type, r.status ?? 'pending', r.nv ?? null, r.details ?? null]);
  if (!res.ok) throw new Error(`إنشاء الطلب فشل (${r.type}): ${res.err}`);
  return res.rows[0].id;
}
let childN = 500;
async function newChild(father) {   // ابن أضافه الأب للتو (شرط حارس الإدراج لـ child_add)
  const cid = id(childN++);
  await db.exec(`insert into profiles(id, first_name, full_name, gender, role, status, father_id)
    values ('${cid}', 'ابن', 'ابن جديد ${childN}', 'male', 'member', 'pending', '${father}')`);
  return cid;
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
async function direct(who, rid, statusTo) {   // كتابة مباشرة كما في النسخ القديمة
  await clearNotes();
  return as(who, `update admin_requests set status = $2 where id = $1 and status = 'pending'`, [rid, statusTo]);
}
async function tick() {
  await clearNotes();
  const r = await as('maint', `select public.approvals_sla_tick() as r`);
  return r.ok ? r.rows[0].r : { err: r.err };
}
const age = (rid, hours) => as('maint', `update admin_requests set stage_since = now() - make_interval(hours => $2) where id = $1`, [rid, hours]);
const req = async rid => one(`select * from admin_requests where id = $1`, [rid]);
const steps = async rid => q(`select action, actor_id, actor_role, note, subject_id from admin_request_steps
  where request_id = $1 order by created_at, action`, [rid]);
const notes = async () => q(`select * from notifications order by target_member_id`);
const targets = async () => (await notes()).map(v => v.target_member_id);
const refused = (label, r, hint) => check(`${label} → ${hint}`, !r.ok && r.hint === hint, r.ok ? 'نجح!' : `${r.hint}: ${r.err}`);
const setSwitch = async on => as(P.O, `update app_settings set approvals_workflow = $1 returning approvals_workflow`, [on]);
const nameOf = async pid => (await one(`select full_name from profiles where id = $1`, [pid])).full_name;
const sameSet =(a, b) => a.length === b.length && [...a].sort().join() === [...b].sort().join();
const MGRS = [P.O, P.A, P.A2];

// ══════════════════════════════════════════════════════════════════════
console.log('\n══════ ١) المفتاح مطفأ = المسار القديم حرفياً ══════');
let rid = await mkreq(P.M1, { member: P.M1, type: 'name_change', nv: 'حسن صلاح عبدالله' });
let x = await req(rid);
check('طلب جديد: عادي، بلا مسار سريع ولا استلام ولا مرحلة ولا خطوات', x.priority === 'normal' && x.fast_track === false
  && x.assigned_to === null && x.stage === null && (await steps(rid)).length === 0);
let r = await as(P.M1, `insert into admin_requests (member_id, requester_id, request_type, new_value, priority, fast_track,
    assigned_to, assigned_at, reminded_at, escalated_at)
  values ($1, $1, 'name_change', 'x', 'urgent', true, $2, now(), now(), now())
  returning priority, fast_track, assigned_to, assigned_at, reminded_at, escalated_at`, [P.M1, P.O]);
check('عضو يرسل أولوية/استلاماً/مساراً سريعاً مفبركاً: يُمسح', r.ok && r.rows[0].priority === 'normal' && r.rows[0].fast_track === false
  && r.rows[0].assigned_to === null && r.rows[0].assigned_at === null && r.rows[0].reminded_at === null && r.rows[0].escalated_at === null,
  r.err ?? JSON.stringify(r.rows));
let kid = await newChild(P.M1);   // إضافة الابن تُشعِر بمزامنة شجرة النساء — قبل مسح الإشعارات
await clearNotes();
const OFF_D = await mkreq(P.S, { member: P.M2, type: 'deceased_report', details: 'وفاة' });
const OFF_C = await mkreq(P.M1, { member: P.M1, type: 'child_add', nv: kid });
check('بلاغ الوفاة وإضافة ابن والمفتاح مطفأ: عاديان، بلا مسار سريع ولا إشعار من المسار',
  (await req(OFF_D)).priority === 'normal' && (await req(OFF_C)).fast_track === false && (await req(OFF_C)).stage === null
  && (await notes()).length === 0);
r = await adv(P.MON, rid, 'claim'); refused('استلام والمفتاح مطفأ', r, 'workflow_off');
r = await adv(P.MON, rid, 'mark_urgent'); refused('أولوية والمفتاح مطفأ', r, 'workflow_off');
let t = await tick();
check('مهمة المهلة والمفتاح مطفأ: لا شيء', t.skipped === 'workflow_off' && t.reminded === 0 && t.escalated === 0, JSON.stringify(t));
r = await as(P.A, `update admin_requests set priority = 'urgent' where id = $1`, [rid]);
refused('المدير يعدّل الأولوية مباشرة', r, 'not_allowed');
r = await as(P.A, `update admin_requests set assigned_to = $2 where id = $1`, [rid, P.A]);
refused('المدير يستلم بالكتابة المباشرة', r, 'not_allowed');
r = await as(P.A, `update admin_requests set escalated_at = now() where id = $1`, [rid]);
refused('المدير يصعّد بالكتابة المباشرة', r, 'not_allowed');
r = await decide(P.MON, rid, 'approve');
check('المراقب يقبل مباشرة كما اليوم', r.ok && (await req(rid)).status === 'approved' && (await steps(rid)).length === 0, r.err ?? '');
r = await direct(P.A, OFF_C, 'rejected');
check('الكتابة المباشرة (أندرويد/الموقع) كما اليوم', r.ok && (await req(OFF_C)).status === 'rejected', r.err ?? '');

console.log('\n══════ ٢) الإعدادات: يقرؤها كل مسجّل ويعدّلها المالك ══════');
r = await as(P.M2, `select approvals_fast_types, approvals_sla_hours, approvals_escalate_hours, approvals_urgent_sla_hours,
  approvals_urgent_escalate_hours from app_settings`);
check('القيم الافتراضية: إضافة ابن سريع، ٢٤/٤٨ عادي، ٦/١٢ مستعجل', r.ok && JSON.stringify(r.rows[0].approvals_fast_types) === '["child_add"]'
  && r.rows[0].approvals_sla_hours === 24 && r.rows[0].approvals_escalate_hours === 48
  && r.rows[0].approvals_urgent_sla_hours === 6 && r.rows[0].approvals_urgent_escalate_hours === 12, JSON.stringify(r.rows ?? r.err));
r = await as(P.A, `update app_settings set approvals_sla_hours = 10 returning 1`);
check('المدير لا يعدّلها (سياسة المالك)', r.ok && r.rows.length === 0);
r = await as(P.O, `update app_settings set approvals_sla_hours = 0`);
check('ساعات صفر مرفوضة (قيد)', !r.ok && /app_settings_approvals_hours_check/.test(r.err), r.err ?? 'قُبل!');
r = await setSwitch(true);
check('المالك يشغّل المسار', r.ok && r.rows[0].approvals_workflow === true);

console.log('\n══════ ٣) الإدراج: المستعجل والمسار السريع ══════');
await clearNotes();
const RD = await mkreq(P.S, { member: P.M2, type: 'deceased_report', details: 'وفاة' });
x = await req(RD); let n = await notes(); let s = await steps(RD);
check('بلاغ الوفاة: مستعجل تلقائياً، «مراجعة»', x.priority === 'urgent' && x.stage === 'review' && x.fast_track === false
  && s.length === 1 && s[0].action === 'submitted', JSON.stringify([x.priority, x.stage, s]));
check('إشعار فوري للمختصين والمالك والمديرين (عدا المرسل)', sameSet(n.map(v => v.target_member_id), [P.MON, P.MON2, ...MGRS])
  && n.every(v => v.title === 'طلب مستعجل: بلاغ الوفاة' && v.body === 'بلاغ الوفاة لـ «عمر صلاح» بانتظار المراجعة' && v.kind === 'admin'
    && v.details?.type === 'approval_workflow' && v.details?.request_id === RD && v.details?.action === 'submitted'
    && v.created_by === P.S && v.request_id === null), JSON.stringify(n.map(v => [v.target_member_id, v.title, v.body])));
kid = await newChild(P.M1);
await clearNotes();
const RF = await mkreq(P.M1, { member: P.M1, type: 'child_add', nv: kid });
x = await req(RF); n = await notes(); s = await steps(RF);
let m1 = await nameOf(P.M1);   // الأسماء تتغيّر بتنفيذ طلبات تغيير الاسم — تُقرأ وقت الفحص
check('إضافة ابن (مسار سريع): مباشرة «اعتماد»، عادي', x.stage === 'approve' && x.fast_track === true && x.priority === 'normal'
  && x.stage_since !== null, JSON.stringify([x.stage, x.fast_track, x.priority]));
check('خطوتان: «submitted» ثم «fast_track» (مسار سريع — مباشرة للمدير)', s.length === 2 && s[0].action === 'submitted'
  && s[0].actor_id === P.M1 && s[1].action === 'fast_track' && s[1].note === 'مسار سريع — مباشرة للمدير'
  && s[1].actor_id === null && s[1].actor_role === 'system', JSON.stringify(s));
check('إشعار المالك والمديرين فقط', sameSet(n.map(v => v.target_member_id), MGRS)
  && n.every(v => v.title === 'مسار سريع: طلب إضافة ابن' && v.body === `مسار سريع — مباشرة للمدير: طلب إضافة ابن لـ «${m1}» بانتظار اعتمادك`
    && v.details?.action === 'fast_track' && v.details?.stage === 'approve'), JSON.stringify(n.map(v => [v.target_member_id, v.title, v.body])));
await clearNotes();
const RN = await mkreq(P.M1, { member: P.M1, type: 'name_change', nv: 'حسن الجديد' });
x = await req(RN);
check('طلب عادي: «مراجعة»، عادي، بلا إشعار من المسار', x.stage === 'review' && x.priority === 'normal' && !x.fast_track
  && (await notes()).length === 0);
r = await as(P.M1, `insert into admin_requests (member_id, requester_id, request_type, new_value, priority, fast_track, assigned_to, escalated_at)
  values ($1, $1, 'name_change', 'x', 'urgent', true, $2, now()) returning stage, priority, fast_track, assigned_to, escalated_at`, [P.M1, P.O]);
check('أولوية/مسار سريع/استلام مفبرك والمفتاح شغّال: يُمسح', r.ok && r.rows[0].stage === 'review' && r.rows[0].priority === 'normal'
  && r.rows[0].fast_track === false && r.rows[0].assigned_to === null && r.rows[0].escalated_at === null, r.err ?? JSON.stringify(r.rows));
await as(P.O, `update app_settings set approvals_fast_types = array['child_add', 'deceased_report']`);
await clearNotes();
const RDF = await mkreq(P.S, { member: P.M3, type: 'deceased_report', details: 'وفاة' });
x = await req(RDF); n = await notes();
check('نوع أضافه المالك للمسار السريع ومستعجل: «اعتماد» + مستعجل', x.stage === 'approve' && x.fast_track && x.priority === 'urgent');
check('…المديرون: مستعجل بمسار سريع، والمختصون: مستعجل عند المدير', sameSet(n.map(v => v.target_member_id), [P.MON, P.MON2, ...MGRS])
  && n.filter(v => MGRS.includes(v.target_member_id)).every(v => v.title === 'طلب مستعجل: بلاغ الوفاة'
    && v.body.startsWith('مسار سريع — مباشرة للمدير:'))
  && n.filter(v => [P.MON, P.MON2].includes(v.target_member_id)).every(v => v.body === 'بلاغ الوفاة لـ «سالم صلاح» — بمسار سريع عند المدير'),
  JSON.stringify(n.map(v => [v.target_member_id, v.title, v.body])));
await as(P.O, `update app_settings set approvals_fast_types = array['child_add']`);
r = await as('maint', `insert into admin_requests (member_id, requester_id, request_type, status, priority, stage, assigned_to)
  values ($1, $1, 'name_change', 'pending', 'urgent', 'execute', $2) returning priority, stage, assigned_to, fast_track`, [P.M2, P.MON]);
check('صيانة SQL تحتفظ بقيمها', r.ok && r.rows[0].priority === 'urgent' && r.rows[0].stage === 'execute' && r.rows[0].assigned_to === P.MON,
  r.err ?? JSON.stringify(r.rows));

console.log('\n══════ ٤) الاستلام والترك وأخذ المالك ══════');
r = await adv(P.M2, RN, 'claim'); refused('عضو يستلم', r, 'not_allowed');
r = await adv(P.S, RN, 'claim'); refused('المشرف يستلم طلب شجرة', r, 'not_allowed');
r = await adv(P.A, RN, 'claim'); refused('المدير يستلم وهو «مراجعة» (يوجد مراقب، غير مصعَّد)', r, 'not_allowed');
r = await adv(P.O, RN, 'claim'); refused('المالك يستلم وهو «مراجعة» (ليس مختصاً ولا مصعَّداً)', r, 'not_allowed');
r = await adv(P.MON, RN, 'claim');
x = await req(RN); s = await steps(RN);
check('المراقب يستلم → assigned_to/assigned_at + خطوة «claim»', r.ok && r.res.assigned_to === P.MON && r.res.stage === 'review'
  && r.res.priority === 'normal' && x.assigned_to === P.MON && x.assigned_at !== null && x.stage === 'review'
  && s.at(-1).action === 'claim' && s.at(-1).actor_id === P.MON && s.at(-1).note === null, r.err ?? JSON.stringify(r.res));
r = await adv(P.MON, RN, 'claim');
check('يستلمه مرة ثانية: لا شيء جديد', r.ok && r.res.assigned_to === P.MON && (await steps(RN)).length === s.length, r.err ?? '');
r = await adv(P.MON2, RN, 'claim'); refused('مراقب آخر يستلمه', r, 'claimed_by_other');
check('…والرسالة باسم المستلم الأول', /يتابعه «علي»/.test(r.err ?? ''), r.err);
r = await adv(P.MON2, RN, 'recommend_approve'); refused('مراقب آخر يوصي وهو عند غيره', r, 'claimed_by_other');
r = await adv(P.MON2, RN, 'recommend_reject', 'سبب'); refused('…أو يوصي بالرفض', r, 'claimed_by_other');
r = await adv(P.MON2, RN, 'request_info', 'سؤال'); refused('…أو يطلب معلومات', r, 'claimed_by_other');
r = await adv(P.MON2, RN, 'release'); refused('مراقب آخر يتركه بدل المستلم', r, 'not_allowed');
r = await adv(P.A, RN, 'release');
x = await req(RN); s = await steps(RN);
check('المدير يلغي استلام غيره → «release» + subject_id', r.ok && r.res.assigned_to === null && x.assigned_to === null && x.assigned_at === null
  && s.at(-1).action === 'release' && s.at(-1).actor_id === P.A && s.at(-1).subject_id === P.MON && s.at(-1).note === 'أُلغي الاستلام', r.err ?? JSON.stringify(s.at(-1)));
r = await adv(P.MON2, RN, 'release');
check('ترك طلب غير مستلَم: لا شيء', r.ok && (await steps(RN)).length === s.length, r.err ?? '');
await adv(P.MON, RN, 'claim');
r = await adv(P.MON, RN, 'release');
check('المستلم يتركه بنفسه', r.ok && (await req(RN)).assigned_to === null && (await steps(RN)).at(-1).subject_id === null, r.err ?? '');
r = await adv(P.MON2, RN, 'claim');
check('مراقب آخر يستلمه بعد الترك', r.ok && (await req(RN)).assigned_to === P.MON2, r.err ?? '');
r = await adv(P.MON, RN, 'request_info', 'سؤال'); refused('المراقب الأول يطلب معلومات', r, 'claimed_by_other');
r = await adv(P.MON2, RN, 'request_info', 'أرفق البطاقة');
check('المستلم يطلب معلومات → «معلومات» والاستلام باقٍ', r.ok && r.res.stage === 'info' && r.res.assigned_to === P.MON2
  && (await req(RN)).assigned_to === P.MON2, r.err ?? JSON.stringify(r.res));
r = await adv(P.MON, RN, 'claim'); refused('استلام وهو «معلومات»', r, 'wrong_stage');
r = await adv(P.M1, RN, 'provide_info', 'أرسلتها');
check('صاحب الطلب يرد (الاستلام لا يمنعه) → «مراجعة» والاستلام باقٍ', r.ok && (await req(RN)).stage === 'review'
  && (await req(RN)).assigned_to === P.MON2 && r.res.assigned_to === P.MON2, r.err ?? '');
check('…وإشعار الرد للمختصين كما كان', sameSet(await targets(), [P.MON, P.MON2]));
r = await adv(P.MON, RN, 'recommend_approve'); refused('المراقب الأول يوصي', r, 'claimed_by_other');
r = await adv(P.MON2, RN, 'recommend_approve');
x = await req(RN);
check('المستلم يوصي → «اعتماد» والاستلام يُفكّ', r.ok && x.stage === 'approve' && x.assigned_to === null && x.assigned_at === null
  && x.recommended_by === P.MON2 && r.res.assigned_to === null, r.err ?? '');
const RMON = await mkreq(P.MON, { member: P.MON, type: 'name_change', nv: 'علي الجديد' });
r = await adv(P.MON, RMON, 'claim'); refused('المختص يستلم طلبه هو', r, 'own_request');

console.log('\n══════ ٤ب) الاستلام في «اعتماد»: المالك والمدير ══════');
r = await adv(P.MON, RN, 'claim'); refused('المختص يستلم في «اعتماد»', r, 'not_allowed');
r = await adv(P.A, RN, 'claim');
check('المدير يستلمه في «اعتماد»', r.ok && (await req(RN)).assigned_to === P.A, r.err ?? '');
r = await adv(P.A2, RN, 'claim'); refused('مدير آخر يستلمه', r, 'claimed_by_other');
check('…«يتابعه «بدر»»', /يتابعه «بدر»/.test(r.err ?? ''), r.err);
r = await adv(P.A2, RN, 'approve'); refused('مدير آخر يعتمد', r, 'claimed_by_other');
r = await adv(P.A2, RN, 'return', 'ملاحظة'); refused('مدير آخر يرجّع', r, 'claimed_by_other');
r = await decide(P.A2, RN, 'reject', 'لا'); refused('مدير آخر يرفض (decide_admin_request)', r, 'claimed_by_other');
r = await decide(P.A2, RN, 'approve'); refused('مدير آخر يعتمد وينفّذ مباشرة (decide_admin_request)', r, 'claimed_by_other');
r = await direct(P.A2, RN, 'rejected'); refused('مدير آخر يرفض بالكتابة المباشرة', r, 'claimed_by_other');
check('لا شيء تغيّر', (await req(RN)).status === 'pending' && (await req(RN)).stage === 'approve' && (await req(RN)).assigned_to === P.A);
r = await adv(P.O, RN, 'claim');
x = await req(RN); s = await steps(RN);
check('المالك يأخذه من المدير → «claim» (أخذه المالك) + subject_id', r.ok && x.assigned_to === P.O && s.at(-1).action === 'claim'
  && s.at(-1).note === 'أخذه المالك' && s.at(-1).subject_id === P.A, r.err ?? JSON.stringify(s.at(-1)));
r = await adv(P.A, RN, 'claim'); refused('المدير يستلم ما عند المالك', r, 'claimed_by_other');
r = await adv(P.O, RN, 'release');
await adv(P.A, RN, 'claim');
r = await adv(P.O, RN, 'approve');
x = await req(RN); n = await notes();
check('المالك يعتمد وهو عند المدير (مستثنى) → «تنفيذ» ويعود الاستلام لمن أوصى', r.ok && x.stage === 'execute'
  && x.assigned_to === P.MON2 && x.assigned_at !== null && r.res.assigned_to === P.MON2, r.err ?? JSON.stringify(x.assigned_to));
check('…وإشعار التنفيذ كما كان (المختصون + صاحب الطلب)', sameSet(n.map(v => v.target_member_id), [P.MON, P.MON2, P.M1]));

console.log('\n══════ ٤ج) التنفيذ لمن استلمه ══════');
r = await decide(P.MON, RN, 'approve'); refused('مراقب آخر ينفّذ (decide_admin_request)', r, 'claimed_by_other');
r = await direct(P.MON, RN, 'approved'); refused('…أو بالكتابة المباشرة (نسخة قديمة)', r, 'claimed_by_other');
r = await adv(P.MON, RN, 'claim'); refused('…أو يستلمه', r, 'claimed_by_other');
r = await decide(P.A2, RN, 'approve'); refused('المدير ينفّذ (غير مختص وغير مصعَّد)', r, 'not_allowed');
r = await decide(P.MON2, RN, 'approve');
x = await req(RN);
check('المستلم ينفّذ → مغلق، والاستلام والأولوية باقيان للتاريخ', r.ok && x.status === 'approved' && x.stage === null
  && x.assigned_to === P.MON2 && x.priority === 'normal' && (await steps(RN)).at(-1).action === 'executed', r.err ?? '');
// الإرجاع يعيده لمن أوصى
const RR = await mkreq(P.M2, { member: P.M2, type: 'name_change', nv: 'عمر الجديد' });
await adv(P.MON, RR, 'recommend_approve');
r = await adv(P.A, RR, 'return', 'تأكد من الاسم');
check('المدير يرجّع → «مراجعة» عند من أوصى', r.ok && (await req(RR)).stage === 'review' && (await req(RR)).assigned_to === P.MON
  && r.res.assigned_to === P.MON, r.err ?? '');
r = await adv(P.MON2, RR, 'recommend_approve'); refused('مراقب آخر يوصي بعد الإرجاع', r, 'claimed_by_other');
r = await adv(P.MON, RR, 'recommend_approve', 'تم التأكد');
check('من أوصى يوصي ثانية', r.ok && (await req(RR)).stage === 'approve', r.err ?? '');
// من أوصى لم يعد مختصاً → لا استلام
const RQ = await mkreq(P.M2, { member: P.M2, type: 'name_change', nv: 'عمر ٢' });
await adv(P.MON2, RQ, 'recommend_approve');
await db.exec(`update profiles set status = 'frozen' where id = '${P.MON2}'`);
r = await adv(P.A, RQ, 'approve');
check('اعتماد ومن أوصى مجمّد → «تنفيذ» بلا استلام', r.ok && (await req(RQ)).stage === 'execute' && (await req(RQ)).assigned_to === null, r.err ?? '');
await db.exec(`update profiles set status = 'active' where id = '${P.MON2}'`);
// الرفض في «مراجعة» والطلب عند المختص: للمدير (القيد في «اعتماد» فقط)
const RZ = await mkreq(P.M2, { member: P.M2, type: 'name_change', nv: 'عمر ٣' });
await adv(P.MON, RZ, 'claim');
r = await decide(P.A, RZ, 'reject', 'مكرر');
check('المدير يرفض وهو «مراجعة» عند المختص', r.ok && (await req(RZ)).status === 'rejected', r.err ?? '');

console.log('\n══════ ٥) الأولوية ══════');
const RP = await mkreq(P.M3, { member: P.M3, type: 'name_change', nv: 'سالم الجديد' });
r = await adv(P.M3, RP, 'mark_urgent'); refused('صاحب الطلب يجعله مستعجلاً', r, 'not_allowed');
r = await adv(P.S, RP, 'mark_urgent'); refused('المشرف على طلب شجرة', r, 'not_allowed');
r = await adv(P.FA, RP, 'mark_urgent'); refused('مدير مجمّد', r, 'not_allowed');
r = await adv(P.MON, RP, 'mark_urgent');
x = await req(RP); n = await notes(); s = await steps(RP);
check('المختص يجعله مستعجلاً → priority + خطوة «priority» (مستعجل)', r.ok && r.res.priority === 'urgent' && x.priority === 'urgent'
  && x.stage === 'review' && s.at(-1).action === 'priority' && s.at(-1).note === 'مستعجل', r.err ?? JSON.stringify(s.at(-1)));
check('…ويُشعِر من بيده الطلب (المختصون غير المستلَم، عدا الفاعل)', n.length === 1 && n[0].target_member_id === P.MON2
  && n[0].title === 'طلب مستعجل: طلب تغيير الاسم' && n[0].body === 'طلب تغيير الاسم لـ «سالم صلاح» صار مستعجلاً'
  && n[0].details?.action === 'priority', JSON.stringify(n.map(v => [v.target_member_id, v.title, v.body])));
r = await adv(P.MON, RP, 'mark_urgent');
check('مستعجل مرة ثانية: لا شيء', r.ok && (await steps(RP)).length === s.length && (await notes()).length === 0, r.err ?? '');
await adv(P.MON2, RP, 'claim');
r = await adv(P.A, RP, 'mark_normal');
check('المدير يعيده عادياً (خطوة «عادي»، بلا إشعار)', r.ok && (await req(RP)).priority === 'normal'
  && (await steps(RP)).at(-1).note === 'عادي' && (await notes()).length === 0, r.err ?? '');
r = await adv(P.A, RP, 'mark_urgent');
check('مستعجل وهو مستلَم: الإشعار للمستلم وحده', r.ok && sameSet(await targets(), [P.MON2]), r.err ?? JSON.stringify(await targets()));
r = await adv(P.MON, RMON, 'mark_urgent'); refused('المختص على طلبه هو', r, 'own_request');
const RA = await mkreq(P.A, { member: P.A, type: 'name_change', nv: 'بدر الجديد' });
r = await adv(P.A, RA, 'mark_urgent'); refused('المدير على طلبه هو', r, 'own_request');
const RO = await mkreq(P.O, { member: P.O, type: 'name_change', nv: 'المالك الجديد' });
r = await adv(P.O, RO, 'mark_urgent');
check('المالك على طلبه هو (مستثنى كما في المسار)', r.ok && (await req(RO)).priority === 'urgent', r.err ?? '');
r = await adv(P.MON, RF, 'mark_urgent');
check('مستعجل في «اعتماد» (غير مستلَم): الإشعار للمالك والمديرين', r.ok && sameSet(await targets(), MGRS), r.err ?? JSON.stringify(await targets()));

console.log('\n══════ ٦) المهلة والتصعيد (approvals_sla_tick) ══════');
const T = {};
T.r25 = await mkreq(P.M1, { member: P.M1, type: 'name_change', nv: 'ت١' });            // مراجعة ٢٥س غير مستلَم
T.r49 = await mkreq(P.M2, { member: P.M2, type: 'name_change', nv: 'ت٢' });            // مراجعة ٤٩س عند المراقب
await adv(P.MON, T.r49, 'claim');
T.u7 = await mkreq(P.S, { member: P.M1, type: 'deceased_report', details: 'وفاة' });   // مستعجل ٧س
T.u13 = await mkreq(P.S, { member: P.M3, type: 'deceased_report', details: 'وفاة' });  // مستعجل ١٣س عند فهد
await adv(P.MON2, T.u13, 'claim');
T.i30 = await mkreq(P.M3, { member: P.M3, type: 'name_change', nv: 'ت٥' });
await adv(P.MON, T.i30, 'request_info', 'سؤال');
T.i49 = await mkreq(P.M3, { member: P.M3, type: 'name_change', nv: 'ت٦' });
await adv(P.MON, T.i49, 'request_info', 'سؤال');
T.a25 = await mkreq(P.M1, { member: P.M1, type: 'name_change', nv: 'ت٧' });
await adv(P.MON, T.a25, 'recommend_approve');
T.ac25 = await mkreq(P.M2, { member: P.M2, type: 'name_change', nv: 'ت٨' });
await adv(P.MON, T.ac25, 'recommend_approve'); await adv(P.A, T.ac25, 'claim');
T.e49 = await mkreq(P.M1, { member: P.M1, type: 'name_change', nv: 'حسن بعد التصعيد' });
await adv(P.MON, T.e49, 'recommend_approve'); await adv(P.A, T.e49, 'approve');
T.r23 = await mkreq(P.M2, { member: P.M2, type: 'name_change', nv: 'ت١٠' });
for (const [k, h] of [['r25', 25], ['r49', 49], ['u7', 7], ['u13', 13], ['i30', 30], ['i49', 49], ['a25', 25], ['ac25', 25], ['e49', 49], ['r23', 23]]) await age(T[k], h);
const pre = Object.fromEntries(await Promise.all(Object.entries(T).map(async ([k, v]) => [k, (await steps(v)).length])));
t = await tick();
n = await notes();
m1 = await nameOf(P.M1);
const nfor = (rid, action) => n.filter(v => v.details?.request_id === rid && v.details?.action === action);
check('النتيجة: ٨ تذكيرات و٣ تصعيدات', t.reminded === 8 && t.escalated === 3, JSON.stringify(t));
x = await req(T.r25); s = await steps(T.r25);
check('مراجعة ٢٥س غير مستلَم: تذكير المختصين + reminded_at + خطوة «reminded»', x.reminded_at !== null && x.escalated_at === null
  && sameSet(nfor(T.r25, 'reminded').map(v => v.target_member_id), [P.MON, P.MON2])
  && nfor(T.r25, 'reminded').every(v => v.title === 'تذكير: طلب تغيير الاسم متأخر'
    && v.body === `طلب تغيير الاسم لـ «${m1}» بانتظار المراجعة منذ 25 ساعة` && v.created_by === null && v.details?.stage === 'review')
  && s.at(-1).action === 'reminded' && s.at(-1).actor_id === null && s.at(-1).actor_role === 'system' && s.at(-1).note === 'تذكير تلقائي بعد 25 ساعة',
  JSON.stringify([nfor(T.r25, 'reminded').map(v => [v.target_member_id, v.title, v.body]), s.at(-1)]));
x = await req(T.r49); s = await steps(T.r49);
check('مراجعة ٤٩س عند المراقب: تذكيره وحده ثم تصعيد للمالك والمديرين ويُفكّ الاستلام', x.reminded_at !== null && x.escalated_at !== null
  && x.assigned_to === null && x.assigned_at === null
  && sameSet(nfor(T.r49, 'reminded').map(v => v.target_member_id), [P.MON])
  && sameSet(nfor(T.r49, 'escalated').map(v => v.target_member_id), MGRS)
  && nfor(T.r49, 'escalated').every(v => v.title === 'تصعيد: طلب تغيير الاسم متأخر'
    && v.body === 'طلب تغيير الاسم لـ «عمر صلاح» متأخر في المراجعة منذ 49 ساعة — تقدر تتصرف بدل المختص'),
  JSON.stringify(n.filter(v => v.details?.request_id === T.r49).map(v => [v.target_member_id, v.details.action, v.body])));
check('…الخطوتان «reminded» ثم «escalated» وصاحب الاستلام في subject_id', JSON.stringify(s.slice(-2).map(v => [v.action, v.subject_id]))
  === JSON.stringify([['reminded', P.MON], ['escalated', P.MON]]), JSON.stringify(s.slice(-2)));
check('مستعجل ٧س (مهلته ٦): تذكير بلا تصعيد', (await req(T.u7)).reminded_at !== null && (await req(T.u7)).escalated_at === null
  && sameSet(nfor(T.u7, 'reminded').map(v => v.target_member_id), [P.MON, P.MON2]));
check('مستعجل ١٣س عند فهد (تصعيده ١٢): تذكير فهد + تصعيد', (await req(T.u13)).escalated_at !== null && (await req(T.u13)).assigned_to === null
  && sameSet(nfor(T.u13, 'reminded').map(v => v.target_member_id), [P.MON2]) && nfor(T.u13, 'escalated').length === 3);
check('«معلومات» ٣٠س: لا شيء', (await req(T.i30)).reminded_at === null && n.filter(v => v.details?.request_id === T.i30).length === 0);
check('«معلومات» ٤٩س: تذكير صاحب الطلب «تذكير: الإدارة تنتظر ردّك»', (await req(T.i49)).reminded_at !== null
  && nfor(T.i49, 'reminded').length === 1 && nfor(T.i49, 'reminded')[0].target_member_id === P.M3
  && nfor(T.i49, 'reminded')[0].title === 'تذكير: الإدارة تنتظر ردّك' && (await req(T.i49)).escalated_at === null,
  JSON.stringify(nfor(T.i49, 'reminded').map(v => [v.target_member_id, v.title, v.body])));
check('«اعتماد» ٢٥س غير مستلَم: تذكير المالك والمديرين (بلا تصعيد)', sameSet(nfor(T.a25, 'reminded').map(v => v.target_member_id), MGRS)
  && nfor(T.a25, 'reminded').every(v => v.body === `طلب تغيير الاسم لـ «${m1}» بانتظار اعتمادك منذ 25 ساعة`)
  && (await req(T.a25)).escalated_at === null);
check('«اعتماد» ٢٥س عند المدير: تذكيره وحده', sameSet(nfor(T.ac25, 'reminded').map(v => v.target_member_id), [P.A]));
check('«تنفيذ» ٤٩س عند المراقب: تذكير + تصعيد (بانتظار التنفيذ)', (await req(T.e49)).escalated_at !== null && (await req(T.e49)).assigned_to === null
  && sameSet(nfor(T.e49, 'reminded').map(v => v.target_member_id), [P.MON])
  && nfor(T.e49, 'escalated').every(v => v.body.includes('متأخر في التنفيذ منذ 49 ساعة')));
check('مراجعة ٢٣س: لا شيء', (await req(T.r23)).reminded_at === null && n.filter(v => v.details?.request_id === T.r23).length === 0);
check('الدفع يمر بالمشغّل الحي (push_attempts)', (await q(`select count(*)::int n from push_attempts`))[0].n === n.length && n.length > 0);
const after1 = Object.fromEntries(await Promise.all(Object.entries(T).map(async ([k, v]) => [k, (await steps(v)).length])));
t = await tick();
const after2 = Object.fromEntries(await Promise.all(Object.entries(T).map(async ([k, v]) => [k, (await steps(v)).length])));
check('تشغيل ثانٍ: لا شيء (آمن للتكرار)', t.reminded === 0 && t.escalated === 0 && (await notes()).length === 0
  && JSON.stringify(after1) === JSON.stringify(after2) && JSON.stringify(pre) !== JSON.stringify(after1), JSON.stringify(t));
// بعد التصعيد: المالك/المدير يتصرف بدل المختص
r = await as(P.A, `select public.can_act_as_specialist($1::uuid) e, public.can_act_as_specialist($2::uuid) ne,
  (select public.can_act_as_specialist(a) from admin_requests a where a.id = $1) row_e`, [T.r49, T.r25]);
check('can_act_as_specialist: المدير مختص للمصعَّد فقط (بالمعرّف وبالصف)', r.ok && r.rows[0].e === true && r.rows[0].ne === false
  && r.rows[0].row_e === true, JSON.stringify(r.rows ?? r.err));
r = await as(P.MON, `select public.can_act_as_specialist($1::uuid) a, public.can_act_as_specialist($2::uuid) b`, [T.r49, T.r25]);
check('…والمراقب مختص للاثنين', r.ok && r.rows[0].a === true && r.rows[0].b === true);
r = await as(P.M1, `select public.can_act_as_specialist($1::uuid) a, public.can_act_as_specialist($2::uuid) b`, [T.r49, id(999)]);
check('…والعضو لا، والطلب المجهول لا', r.ok && r.rows[0].a === false && r.rows[0].b === false);
r = await adv(P.A, T.r25, 'recommend_approve'); refused('المدير يوصي على غير المصعَّد', r, 'not_allowed');
r = await adv(P.A, T.r49, 'claim');
check('المدير يستلم المصعَّد في «مراجعة»', r.ok && (await req(T.r49)).assigned_to === P.A, r.err ?? '');
r = await adv(P.A2, T.r49, 'recommend_approve'); refused('مدير آخر يوصي وهو عند المدير', r, 'claimed_by_other');
r = await adv(P.A, T.r49, 'recommend_approve');
x = await req(T.r49);
check('المدير يوصي بدل المختص → «اعتماد»، والمؤقتان يُصفَّران', r.ok && x.stage === 'approve' && x.escalated_at === null
  && x.reminded_at === null && x.assigned_to === null, r.err ?? '');
r = await adv(P.A2, T.r49, 'approve');
x = await req(T.r49);
check('مدير آخر يعتمد → «تنفيذ»، والاستلام لا يعود لمن أوصى (المدير لم يعد مختصاً بعد تصفير التصعيد)', r.ok && x.stage === 'execute'
  && x.assigned_to === null && r.res.assigned_to === null, r.err ?? JSON.stringify(x.assigned_to));
r = await decide(P.A2, T.e49, 'approve');
check('«تنفيذ» مصعَّد: المدير ينفّذ بدل المختص', r.ok && (await req(T.e49)).status === 'approved'
  && (await one(`select full_name from profiles where id = $1`, [P.M1])).full_name === 'حسن بعد التصعيد', r.err ?? '');
r = await adv(P.MON, T.r25, 'recommend_approve');
check('تغيير المرحلة يصفّر التذكير', r.ok && (await req(T.r25)).reminded_at === null, r.err ?? '');
await setSwitch(false);
await age(T.r23, 30);
t = await tick();
check('المفتاح مطفأ: المهمة لا تفعل شيئاً', t.skipped === 'workflow_off' && (await req(T.r23)).reminded_at === null, JSON.stringify(t));
await setSwitch(true);

console.log('\n══════ ٧) قوالب الردود ══════');
r = await as(P.MON, `select kind, count(*)::int n from approval_templates group by kind order by kind`);
check('١٠ قوالب افتراضية يقرؤها المراقب', r.ok && JSON.stringify(r.rows) === JSON.stringify([{ kind: 'info', n: 3 }, { kind: 'note', n: 1 },
  { kind: 'recommend', n: 1 }, { kind: 'reject', n: 4 }, { kind: 'return', n: 1 }]), JSON.stringify(r.rows ?? r.err));
r = await as(P.S, `select count(*)::int n from approval_templates`);
check('المشرف يقرؤها', r.ok && r.rows[0].n === 10);
r = await as(P.M1, `select count(*)::int n from approval_templates`);
check('العضو لا يراها', r.ok && r.rows[0].n === 0);
r = await as(P.FA, `select count(*)::int n from approval_templates`);
check('المدير المجمّد لا يراها', r.ok && r.rows[0].n === 0);
r = await as('anon', `select count(*) from approval_templates`);
check('بلا دخول: ممنوع', !r.ok && /permission denied/.test(r.err), r.err ?? 'قُرئ!');
r = await as(P.A, `insert into approval_templates (kind, body, sort) values ('reject', 'الصورة مقلوبة', 5) returning id, created_by`);
const TPL = r.rows?.[0]?.id;
check('المدير يضيف قالباً (created_by = هو)', r.ok && r.rows[0].created_by === P.A, r.err ?? '');
r = await as(P.A, `insert into approval_templates (kind, body, created_by) values ('note', 'باسم غيري', $1)`, [P.O]);
check('…ولا يضيفه باسم غيره', !r.ok && /row-level security/.test(r.err), r.err ?? 'قُبل!');
r = await as(P.MON, `insert into approval_templates (kind, body) values ('note', 'من المراقب')`);
check('المراقب لا يضيف', !r.ok && /row-level security/.test(r.err), r.err ?? 'قُبل!');
r = await as(P.MON, `update approval_templates set body = 'تعديل' where id = $1 returning 1`, [TPL]);
check('المراقب لا يعدّل', r.ok && r.rows.length === 0);
r = await as(P.O, `update approval_templates set body = 'الصورة مقلوبة، أرسلها معدولة' where id = $1 returning body`, [TPL]);
check('المالك يعدّل', r.ok && r.rows[0]?.body === 'الصورة مقلوبة، أرسلها معدولة', r.err ?? '');
for (const [lbl, k, b] of [['نص فارغ', 'note', ''], ['أطول من ٣٠٠ حرف', 'note', 'ن'.repeat(301)], ['نوع غير معروف', 'praise', 'شكراً']]) {
  r = await as(P.A, `insert into approval_templates (kind, body) values ($1, $2)`, [k, b]);
  check(`قالب ${lbl}: مرفوض`, !r.ok && /check constraint/.test(r.err), r.err ?? 'قُبل!');
}
r = await as(P.MON, `delete from approval_templates where id = $1 returning 1`, [TPL]);
check('المراقب لا يحذف', r.ok && r.rows.length === 0);
r = await as(P.A, `delete from approval_templates where id = $1 returning 1`, [TPL]);
check('المدير يحذف', r.ok && r.rows.length === 1, r.err ?? '');

console.log('\n══════ ٨) الملاحظات الداخلية ══════');
const RNT = await mkreq(P.M1, { member: P.M1, type: 'name_change', nv: 'ملاحظات' });
await adv(P.MON, RNT, 'claim');
await clearNotes();
r = await as(P.A, `insert into admin_request_notes (request_id, body) values ($1, 'تواصلت مع الأب وتأكدت') returning id, author_id`, [RNT]);
const NOTE_A = r.rows?.[0]?.id;
n = await notes();
check('المدير يكتب ملاحظة (author_id = هو)', r.ok && r.rows[0].author_id === P.A, r.err ?? '');
check('…وتُشعِر المستلم «ملاحظة داخلية على …»', n.length === 1 && n[0].target_member_id === P.MON
  && n[0].title === `ملاحظة داخلية على طلب تغيير الاسم لـ «${await nameOf(P.M1)}»` && n[0].body === 'بدر: تواصلت مع الأب وتأكدت'
  && n[0].created_by === P.A && n[0].details?.action === 'note' && n[0].details?.request_id === RNT, JSON.stringify(n.map(v => [v.target_member_id, v.title, v.body])));
await clearNotes();
r = await as(P.MON, `insert into admin_request_notes (request_id, body) values ($1, 'سأتصل غداً') returning id`, [RNT]);
const NOTE_MON = r.rows?.[0]?.id;
check('المستلم يكتب ملاحظة: بلا إشعار لنفسه', r.ok && (await notes()).length === 0, r.err ?? '');
r = await as(P.M1, `select count(*)::int n from admin_request_notes where request_id = $1`, [RNT]);
check('صاحب الطلب لا يرى الملاحظات', r.ok && r.rows[0].n === 0);
r = await as(P.M2, `select count(*)::int n from admin_request_notes`);
check('عضو آخر لا يراها', r.ok && r.rows[0].n === 0);
r = await as(P.S, `select count(*)::int n from admin_request_notes where request_id = $1`, [RNT]);
check('الإدارة تراها (المشرف)', r.ok && r.rows[0].n === 2);
r = await as(P.M1, `insert into admin_request_notes (request_id, body) values ($1, 'من صاحب الطلب')`, [RNT]);
check('صاحب الطلب لا يكتب', !r.ok && /row-level security/.test(r.err), r.err ?? 'قُبل!');
r = await as(P.MON, `insert into admin_request_notes (request_id, author_id, body) values ($1, $2, 'باسم المدير')`, [RNT, P.A]);
check('لا ملاحظة باسم غيرك', !r.ok && /row-level security/.test(r.err), r.err ?? 'قُبل!');
const RA2N = await mkreq(P.A2, { member: P.A2, type: 'name_change', nv: 'خالد ٢' });
await clearNotes();
r = await as(P.MON, `insert into admin_request_notes (request_id, body) values ($1, 'عن طلب المدير')`, [RA2N]);
check('ملاحظة على طلب غير مستلَم: بلا إشعار', r.ok && (await notes()).length === 0, r.err ?? '');
r = await as(P.A2, `select count(*)::int n from admin_request_notes where request_id = $1`, [RA2N]);
check('المدير لا يرى الملاحظات على طلبه هو', r.ok && r.rows[0].n === 0);
r = await as(P.A2, `insert into admin_request_notes (request_id, body) values ($1, 'على طلبي')`, [RA2N]);
check('…ولا يكتب عليه', !r.ok && /row-level security/.test(r.err), r.err ?? 'قُبل!');
r = await as(P.O, `select count(*)::int n from admin_request_notes where request_id = $1`, [RA2N]);
check('المالك يراها', r.ok && r.rows[0].n === 1);
r = await as(P.A, `delete from admin_request_notes where id = $1 returning 1`, [NOTE_MON]);
check('لا حذف لملاحظة غيرك', r.ok && r.rows.length === 0);
r = await as(P.MON, `delete from admin_request_notes where id = $1 returning 1`, [NOTE_MON]);
check('حذف ملاحظتك', r.ok && r.rows.length === 1, r.err ?? '');
r = await as(P.A, `update admin_request_notes set body = 'تعديل' where id = $1`, [NOTE_A]);
check('لا تعديل للملاحظات', !r.ok && /permission denied/.test(r.err), r.err ?? 'عُدّل!');
for (const [lbl, b] of [['فارغة', ''], ['أطول من ١٠٠٠ حرف', 'م'.repeat(1001)]]) {
  r = await as(P.A, `insert into admin_request_notes (request_id, body) values ($1, $2)`, [RNT, b]);
  check(`ملاحظة ${lbl}: مرفوضة`, !r.ok && /check constraint/.test(r.err), r.err ?? 'قُبل!');
}
r = await as('anon', `select count(*) from admin_request_notes`);
check('بلا دخول: ممنوع', !r.ok && /permission denied/.test(r.err), r.err ?? 'قُرئ!');

console.log('\n══════ ٩) تقرير الأداء (approvals_report) ══════');
// أربعة طلبات بأوقات محدّدة في ١٠ يناير ٢٠٢٦ (تُزاح بالصيانة بعد المسار الحقيقي)
const RP1 = await mkreq(P.M2, { member: P.M2, type: 'name_change', nv: 'عمر التقرير' });
await adv(P.MON, RP1, 'recommend_approve'); await adv(P.A, RP1, 'approve'); await decide(P.MON, RP1, 'approve');
const RP2 = await mkreq(P.M3, { member: P.M3, type: 'name_change', nv: 'سالم التقرير' });
await adv(P.MON, RP2, 'request_info', 'سؤال'); await adv(P.M3, RP2, 'provide_info', 'جواب');
await adv(P.MON, RP2, 'recommend_reject', 'غير مطابق'); await decide(P.A, RP2, 'reject', 'غير مطابق');
const RP3 = await mkreq(P.S, { member: P.M3, type: 'deceased_report', details: 'وفاة' });
await adv(P.MON, RP3, 'claim'); await age(RP3, 13); await tick();
const RP4 = await mkreq(P.M1, { member: P.M1, type: 'child_add', nv: await newChild(P.M1) });
check('طلبات التقرير جاهزة', (await req(RP1)).status === 'approved' && (await req(RP2)).status === 'rejected'
  && (await req(RP3)).escalated_at !== null && (await req(RP4)).fast_track === true);
const T0 = Date.parse('2026-01-10T08:00:00Z');
const at = h => new Date(T0 + h * 3600e3).toISOString();
const shift = async (rid, plan) => {
  await as('maint', `update admin_requests set created_at = $2 where id = $1`, [rid, at(0)]);
  for (const [action, h] of plan) await as('maint', `update admin_request_steps set created_at = $3 where request_id = $1 and action = $2`, [rid, action, at(h)]);
};
await shift(RP1, [['submitted', 0], ['recommend_approve', 2], ['approve', 3], ['executed', 5]]);
await shift(RP2, [['submitted', 0], ['request_info', 1], ['provide_info', 4], ['recommend_reject', 5], ['rejected', 6]]);
await shift(RP3, [['submitted', 0], ['claim', 0.5], ['reminded', 7], ['escalated', 13]]);
await shift(RP4, [['submitted', 0], ['fast_track', 0.001 / 3600]]);
const report = async (who, f, to) => {
  const res = await as(who, `select public.approvals_report($1::timestamptz, $2::timestamptz) as r`, [f, to]);
  return res.ok ? { ok: true, res: res.rows[0].r } : res;
};
for (const [who, lbl] of [[P.M1, 'عضو'], [P.S, 'المشرف'], [P.FA, 'مدير مجمّد'], [P.PEND, 'معلّق']]) {
  r = await report(who, at(0), at(24)); refused(`التقرير: ${lbl}`, r, 'not_allowed');
}
r = await report(P.A, at(24), at(0)); refused('فترة مقلوبة', r, 'bad_range');
r = await report(P.MON, at(0), at(24));
const R_ = r.res;
check('المراقب يقرأ التقرير', r.ok, r.err ?? '');
check('شكل التقرير: المفاتيح كما في العقد', r.ok && JSON.stringify(Object.keys(R_).sort()) === '["period","staff","stages","totals","types"]'
  && JSON.stringify(Object.keys(R_.period).sort()) === '["from","to"]'
  && JSON.stringify(Object.keys(R_.totals).sort()) === JSON.stringify(['escalated', 'executed', 'fast_track', 'overdue_now', 'pending', 'rejected', 'submitted', 'urgent'])
  && JSON.stringify(Object.keys(R_.stages).sort()) === JSON.stringify(['approve_hours', 'execute_hours', 'info_hours', 'review_hours'])
  && R_.types.every(v => JSON.stringify(Object.keys(v).sort()) === '["count","executed","label","rejected","type"]')
  && R_.staff.every(v => JSON.stringify(Object.keys(v).sort()) === JSON.stringify(['actions', 'avg_response_hours', 'escalations', 'member_id', 'name', 'role'])),
  JSON.stringify(R_));
check('الفترة', r.ok && Date.parse(R_.period.from) === T0 && Date.parse(R_.period.to) === T0 + 24 * 3600e3, JSON.stringify(R_?.period));
const overdue = (await one(`select count(*)::int n from admin_requests o where o.status = 'pending' and o.stage is not null
  and o.request_type <> 'contact_message' and now() - coalesce(o.stage_since, o.created_at)
  >= make_interval(hours => case when o.stage = 'info' then 48 when o.priority = 'urgent' then 6 else 24 end)`)).n;
check('الإجماليات: ٤ مرسلة، ١ نُفّذ، ١ رُفض، ٢ معلّقة، ١ مستعجل، ١ مصعَّد، ١ سريع، والمتأخر الآن',
  r.ok && JSON.stringify(R_.totals) === JSON.stringify({ urgent: 1, pending: 2, executed: 1, rejected: 1, escalated: 1, submitted: 4,
    fast_track: 1, overdue_now: overdue }) && overdue > 0, JSON.stringify(R_?.totals) + ' overdue=' + overdue);
check('متوسطات المراحل بالساعات (مراجعة ١٫٣، اعتماد ١، تنفيذ ٢، معلومات ٣)', r.ok && R_.stages.review_hours === 1.3
  && R_.stages.approve_hours === 1 && R_.stages.execute_hours === 2 && R_.stages.info_hours === 3, JSON.stringify(R_?.stages));
const norm = o => JSON.stringify(Object.keys(o).sort().map(k => [k, o[k]]));   // jsonb يرتّب المفاتيح بطولها
check('الأنواع بالعدد ثم الاسم مع الاسم العربي', r.ok && JSON.stringify(R_.types.map(norm)) === JSON.stringify([
  { type: 'name_change', count: 2, label: 'طلب تغيير الاسم', executed: 1, rejected: 1 },
  { type: 'child_add', count: 1, label: 'طلب إضافة ابن', executed: 0, rejected: 0 },
  { type: 'deceased_report', count: 1, label: 'بلاغ الوفاة', executed: 0, rejected: 0 }].map(norm)), JSON.stringify(R_?.types));
check('الإدارة: المراقب (٥ إجراءات، ١٫٥ ساعة، تصعيد ١) ثم المدير (٢، ١ ساعة)', r.ok && R_.staff.length === 2
  && R_.staff[0].member_id === P.MON && R_.staff[0].name === 'علي المراقب' && R_.staff[0].role === 'monitor'
  && R_.staff[0].actions === 5 && R_.staff[0].avg_response_hours === 1.5 && R_.staff[0].escalations === 1
  && R_.staff[1].member_id === P.A && R_.staff[1].actions === 2 && R_.staff[1].avg_response_hours === 1 && R_.staff[1].escalations === 0,
  JSON.stringify(R_?.staff));
r = await report(P.O, '2030-01-01T00:00:00Z', '2030-02-01T00:00:00Z');
check('فترة بلا طلبات: أصفار وقوائم فارغة ومتوسطات null', r.ok && r.res.totals.submitted === 0 && r.res.totals.executed === 0
  && r.res.stages.review_hours === null && r.res.stages.info_hours === null
  && JSON.stringify(r.res.types) === '[]' && JSON.stringify(r.res.staff) === '[]', JSON.stringify(r.res ?? r.err));
r = await as(P.A, `select public.approvals_report() as r`);
check('بلا معاملات: آخر ٣٠ يوماً', r.ok && Math.abs(Date.parse(r.rows[0].r.period.to) - Date.parse(r.rows[0].r.period.from) - 30 * 86400e3) < 5000
  && r.rows[0].r.totals.submitted > 0, r.err ?? JSON.stringify(r.rows?.[0]?.r?.period));

console.log('\n══════ ١٠) الصلاحيات والجدولة ══════');
r = await as('maint', `select
  has_function_privilege('authenticated', 'public.advance_admin_request(uuid,text,text,text[],jsonb)', 'execute') adv_a,
  has_function_privilege('anon', 'public.advance_admin_request(uuid,text,text,text[],jsonb)', 'execute') adv_n,
  has_function_privilege('authenticated', 'public.approvals_report(timestamptz,timestamptz)', 'execute') rep_a,
  has_function_privilege('anon', 'public.approvals_report(timestamptz,timestamptz)', 'execute') rep_n,
  has_function_privilege('authenticated', 'public.can_act_as_specialist(uuid)', 'execute') cas_a,
  has_function_privilege('anon', 'public.can_act_as_specialist(uuid)', 'execute') cas_n,
  has_function_privilege('authenticated', 'public.can_act_as_specialist(public.admin_requests)', 'execute') casr_a,
  has_function_privilege('anon', 'public.can_act_as_specialist(public.admin_requests)', 'execute') casr_n,
  has_function_privilege('authenticated', 'public.approvals_sla_tick()', 'execute') tick_a,
  has_function_privilege('anon', 'public.approvals_sla_tick()', 'execute') tick_n,
  has_function_privilege('authenticated', 'public.approvals_member_can_specialize(uuid,text)', 'execute') h1,
  has_function_privilege('authenticated', 'public.approvals_first_name(uuid)', 'execute') h2,
  has_function_privilege('authenticated', 'public.approvals_raise_claimed(uuid)', 'execute') h3,
  has_function_privilege('authenticated', 'public.approvals_manager_ids()', 'execute') h4,
  has_function_privilege('authenticated', 'public.notify_admin_request_note()', 'execute') h5,
  has_table_privilege('anon', 'public.approval_templates', 'select') t_n,
  has_table_privilege('anon', 'public.admin_request_notes', 'select') n_n,
  has_table_privilege('authenticated', 'public.admin_request_notes', 'update') n_u,
  (select count(*)::int from pg_proc where proname = 'advance_admin_request') adv_count,
  (select pg_get_function_arguments(oid) from pg_proc where proname = 'advance_admin_request') adv_args`);
const g = r.rows?.[0] ?? {};
check('authenticated تنفّذ advance (٥ معاملات) والتقرير و can_act_as_specialist (بالمعرّف والصف)، anon لا',
  g.adv_a && !g.adv_n && g.rep_a && !g.rep_n && g.cas_a && !g.cas_n && g.casr_a && !g.casr_n, JSON.stringify(g));
check('approvals_sla_tick والمساعدات داخلية فقط', !g.tick_a && !g.tick_n && !g.h1 && !g.h2 && !g.h3 && !g.h4 && !g.h5, JSON.stringify(g));
check('الجداول الجديدة: لا anon، ولا تعديل للملاحظات', !g.t_n && !g.n_n && !g.n_u);
check('دالة واحدة advance_admin_request بالتوقيع نفسه', g.adv_count === 1
  && g.adv_args === 'p_request_id uuid, p_action text, p_note text DEFAULT NULL::text, p_fields text[] DEFAULT NULL::text[], p_values jsonb DEFAULT NULL::jsonb', g.adv_args);
r = await as(P.M1, `select public.approvals_sla_tick()`);
check('المستخدم لا يشغّل مهمة المهلة', !r.ok && /permission denied/.test(r.err), r.err ?? 'شغّلها!');
r = await q(`select jobname, schedule, command, username from cron.job where jobname = 'approvals-sla'`);
check(`مهمة pg_cron 'approvals-sla' كل ١٥ دقيقة`, r.length === 1 && r[0].schedule === '*/15 * * * *'
  && r[0].command === 'select public.approvals_sla_tick()', JSON.stringify(r));

console.log('\n══════ ١١) التراجع ══════');
await db.exec(v2rb);
const afterRb = await deepShape();
check('التراجع يعيد حالة 20261015170000 حرفياً (أعمدة، صلاحيات، دوال، قيود، مشغّلات، سياسات، فهارس، تعليقات، cron)',
  afterRb === before, afterRb === before ? '' : 'مختلف');
m5 = await liveMd5();
check('…ونصوص الدوال الأربع = md5 الحي', sameMd5(m5), JSON.stringify(m5));
check('…ومهمة approvals-sla أُزيلت، والجدولان', (await q(`select 1 from cron.job where jobname = 'approvals-sla'`)).length === 0
  && (await q(`select 1 from pg_tables where tablename in ('approval_templates', 'admin_request_notes')`)).length === 0);
check('…والطلبات المعلّقة كما هي (السريع يبقى «اعتماد»)', (await req(RF)).stage === 'approve' && (await req(RF)).status === 'pending'
  && (await q(`select count(*)::int n from admin_request_steps where action not in ('submitted', 'recommend_approve', 'recommend_reject',
    'request_info', 'provide_info', 'approve', 'return', 'executed', 'rejected')`))[0].n === 0);
r = await adv(P.MON, RN, 'claim'); refused('بعد التراجع: claim إجراء مجهول', r, 'bad_action');
const RB1 = await mkreq(P.M1, { member: P.M1, type: 'name_change', nv: 'بعد التراجع' });
r = await adv(P.MON, RB1, 'recommend_approve');
check('بعد التراجع: المسار كما كان', r.ok && (await req(RB1)).stage === 'approve', r.err ?? '');
await db.exec(v2);
check('إعادة التطبيق بعد التراجع تعمل', (await deepShape()) === once);
await db.exec(v2rb);
check('وتراجع ثانٍ يعيد الحي حرفياً', (await deepShape()) === before);
await db.close();

console.log('\n══════ ١٢) التجارب القائمة والترحيل مثبّت ══════');
// تجربة المسار كاملة (١٥٩) والترحيل مثبّت بعد «طلب معلومات» منظّم؛ قسم التراجع فيها يبدأ بتراجع هذا الترحيل
function replay(file, swaps, label) {
  let src = readFileSync(HERE + file, 'utf8');
  for (const [anchor, add, prepend] of swaps) {
    if (!src.includes(anchor)) { check(`${label}: نقطة الحقن موجودة`, false, anchor); return; }
    src = src.replace(anchor, () => prepend ? `${add}\n${anchor}` : `${anchor}\n${add}`);
  }
  const tmp = `${HERE}.v2_replay_${file}`;
  writeFileSync(tmp, src);
  try {
    const run = spawnSync(process.execPath, [tmp], { cwd: HERE, encoding: 'utf8', maxBuffer: 64 << 20 });
    const summary = (run.stdout.match(/النتيجة: \d+ نجح، \d+ فشل/g) ?? ['']).at(-1);
    const failed = run.stdout.split('\n').filter(l => l.startsWith('❌')).slice(0, 5).join(' | ');
    check(label, run.status === 0, summary + (failed ? ' ' + failed : '') + (run.status ? ' ' + run.stderr.slice(-600) : ''));
  } finally { unlinkSync(tmp); }
}
const ex = sql => `await db.exec(${JSON.stringify(sql)});`;
replay('approvals_workflow.test.mjs', [
  ['await db.exec(infoMig);', ex(CRON + v2)],
  ['await db.exec(infoRollback);', ex(v2rb), true]],
  'approvals_workflow.test.mjs كاملة وهذا الترحيل مثبّت (المفتاح مطفأ ثم شغّال، والتراجعات)');
const settings = on => `create table if not exists public.app_settings (id uuid primary key default gen_random_uuid(),
  news_requires_approval boolean not null default true); insert into public.app_settings default values;
  alter table public.notifications add column if not exists details jsonb;
  ${CRON}
  ${wfMig}
  ${ownerFix}
  ${infoMig}
  ${v2}
  update public.app_settings set approvals_workflow = ${on};`;
replay('decide_admin_request.test.mjs', [['await db.exec(live); await db.exec(guard); await db.exec(mig);', ex(settings(false))]],
  'decide_admin_request.test.mjs كاملة والترحيلات الأربعة مثبّتة (المفتاح مطفأ)');
replay('admin_requests_guard.test.mjs', [['if (withGuard) await db.exec(guard);', ex(settings(false))]],
  'admin_requests_guard.test.mjs كاملة والترحيلات الأربعة مثبّتة (المفتاح مطفأ)');
replay('admin_requests_guard.test.mjs', [['if (withGuard) await db.exec(guard);', ex(settings(true))]],
  'admin_requests_guard.test.mjs كاملة والمفتاح شغّال (الإدراج لا يُرفض بالمستعجل/السريع)');

console.log(`\nالنتيجة: ${pass} نجح، ${fail} فشل`);
process.exit(fail ? 1 : 0);
