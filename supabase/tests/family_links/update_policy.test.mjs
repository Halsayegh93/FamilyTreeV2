// تجربة 20261107230000_update_policy («فرض التحديث» من جديد: اختياري · إجباري من تاريخ · إجباري، و«النسخ عند الأعضاء»)
// على قاعدة محلية معزولة — لا تلمس السيرفر. app_config وفحصه وسجلّه وset_app_config وapp_config() منسوخة حرفياً من الحي
// (md5 مطابقة، ٢٠٢٦-١١-٠٧)، وapp_settings وdevice_tokens بأعمدة الحي وسياساته. يثبت: المفاتيح تُضاف وتمرّ فحصها وتصل كل
// مسجّل، رسالة المالك القديمة تنتقل، الحالة تُحسب على السيرفر (لا شيء · اختياري · من تاريخ بعدّ و«لاحقاً» تختفي آخر يوم ·
// إجباري بعد الموعد/الحين/تحت الحد) والمالك لا ينقفل، الحفظ للمالك وحده بفحص العلاقات، الجهاز يبلّغ نسخته لنفسه فقط،
// «النسخ عند الأعضاء» للمالك وحده بالأرقام الصحيحة، لا دالة حيّة تتغيّر، إعادة التطبيق آمنة، والتراجع نظيف.
// التشغيل: cd supabase/tests/family_links && node update_policy.test.mjs
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
process.on('unhandledRejection', e => { console.log('خطأ:', e.message, (e.query ?? '').slice(0, 300)); process.exit(2); });

const REPO = fileURLToPath(new URL('../../', import.meta.url));
const MIG = readFileSync(`${REPO}/migrations/20261107230000_update_policy.sql`, 'utf8');
const RB = readFileSync(`${REPO}/rollback/20261107230000_update_policy_rollback.sql`, 'utf8');
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const O = id(1), A = id(2), MON = id(3), S = id(4), M = id(5);
let pass = 0, fail = 0;
const ok = (c, m, x = '') => { if (c) { pass++; console.log('✓', m); } else { fail++; console.log('✗', m, x); } };
// نص الحي بعلامات بدل الشرطة المائلة وU+FFFF وعلامة `
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
create table public.profiles (id uuid primary key, role text, status text, full_name text, first_name text);
create function public.current_profile_id() returns uuid language sql stable as $$ select auth.uid() $$;
create function public.current_user_role() returns text language sql stable security definer set search_path to 'public' as $$
  select case when p.status = 'active' then p.role when p.status in ('frozen','deleted') then p.status else 'pending' end
  from public.profiles p where p.id = public.current_profile_id() $$;
-- app_settings بأعمدة التحديث الحية (معرّف uuid صف واحد)
create table public.app_settings (id uuid primary key default '00000000-0000-0000-0000-000000000001', sms_wait_seconds int default 60,
  allow_new_registrations boolean default true, updated_at timestamptz default now(), updated_by uuid,
  ios_min_build int not null default 0, android_min_build int not null default 0, ios_update_url text, android_update_url text,
  latest_build int not null default 0, force_update boolean not null default false, update_message text);
insert into public.app_settings (id, android_min_build, update_message) values (default, 2, 'رسالة المالك القديمة');
-- device_tokens بقيود وسياسات الحي
create table public.device_tokens (id bigserial primary key, member_id uuid references public.profiles(id) on delete cascade,
  token text not null default '', platform text default 'ios', created_at timestamptz default now(), updated_at timestamptz default now(),
  device_name text, device_id text, environment text default 'production' check (environment in ('sandbox', 'production')));
create unique index idx_device_tokens_member_device_unique on public.device_tokens (member_id, device_id);
alter table public.device_tokens enable row level security;
grant select, insert, update, delete on public.device_tokens to authenticated;
grant usage on sequence public.device_tokens_id_seq to authenticated;
create policy device_tokens_update_self on public.device_tokens for update using (member_id = auth.uid()) with check (member_id = auth.uid());
create policy device_tokens_insert_self on public.device_tokens for insert with check (member_id = auth.uid());
create policy device_tokens_select_self_or_owner on public.device_tokens for select
  using (member_id = auth.uid() or public.current_user_role() = 'owner');
-- app_config بقيود الحي
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

// ═══ الحي حرفياً (pg_get_functiondef ٢٠٢٦-١٠-٢٥) ═══
await db.exec(unmark(`CREATE OR REPLACE FUNCTION private.app_config_text_problem(p_text text, p_multiline boolean, p_max_length integer, p_rules jsonb)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare
  v_len  integer := char_length(p_text);
  v_min  integer := coalesce((p_rules ->> 'min_length')::integer, 1);
  v_tok  text;
  v_bare text := p_text;
begin
  if v_len < v_min then
    return case when v_min <= 1 then 'النص مطلوب' else 'النص أقصر من ' || v_min || ' أحرف' end;
  end if;
  if p_max_length is not null and v_len > p_max_length then
    return 'النص أطول من ' || p_max_length || ' حرفاً';
  end if;
  if p_text ~ (case when p_multiline then '[<BS>x01-<BS>x09<BS>x0b-<BS>x1f<BS>x7f]' else '[<BS>x01-<BS>x1f<BS>x7f]' end) then
    return case when p_multiline then 'النص فيه رموز غير مسموحة' else 'النص يجب أن يكون في سطر واحد' end;
  end if;
  for v_tok in select jsonb_array_elements_text(coalesce(p_rules -> 'placeholders', '[]'::jsonb)) loop
    if position(v_tok in p_text) = 0 then
      return 'النص يجب أن يحتوي ' || v_tok;
    end if;
    if coalesce((p_rules ->> 'single_placeholders')::boolean, false)
       and position(v_tok in substr(p_text, position(v_tok in p_text) + char_length(v_tok))) > 0 then
      return 'النص يجب أن يحتوي ' || v_tok || ' مرة واحدة فقط';
    end if;
    v_bare := replace(v_bare, v_tok, '');
  end loop;
  if p_rules ? 'pattern' and p_text !~ (p_rules ->> 'pattern') then
    return coalesce(p_rules ->> 'pattern_ar', 'صيغة النص غير صحيحة');
  end if;
  if coalesce((p_rules ->> 'bmp_only')::boolean, false) and p_text ~ '[^<BS>x01-<FFFF>]' then
    return 'النص فيه رموز (مثل الوجوه التعبيرية) لا تصلح لرسالة الرمز';
  end if;
  if coalesce((p_rules ->> 'sms_gsm')::boolean, false) and v_bare ~ '[^ -~]|[][{}<BS><BS>^~|<BT>]' then
    return 'الرسالة الإنجليزية: حروف وأرقام إنجليزية وعلامات بسيطة فقط';
  end if;
  return null;
end;
$function$
`));
await db.exec(`CREATE OR REPLACE FUNCTION private.app_config_problem(p_kind text, p_value jsonb, p_min numeric, p_max numeric, p_max_length integer, p_rules jsonb)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare
  v_type  text := jsonb_typeof(p_value);
  v_items text := p_rules ->> 'items';
  v_uuid  text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_range text := 'بين ' || coalesce(p_min::text, '…') || ' و' || coalesce(p_max::text, '…');
  v_num   numeric;
  v_prev  numeric;
  v_item  jsonb;
  v_key   text;
  v_n     integer;
  v_msg   text;
begin
  if p_value is null or v_type = 'null' then
    return 'القيمة مطلوبة';
  end if;
  if p_kind = 'int' then
    if v_type <> 'number' then return 'القيمة يجب أن تكون رقماً صحيحاً'; end if;
    v_num := (p_value #>> '{}')::numeric;
    if v_num <> trunc(v_num) then return 'القيمة يجب أن تكون رقماً صحيحاً'; end if;
    if (p_min is not null and v_num < p_min) or (p_max is not null and v_num > p_max) then
      return 'القيمة يجب أن تكون ' || v_range;
    end if;
    return null;
  elsif p_kind = 'bool' then
    return case when v_type = 'boolean' then null else 'القيمة يجب أن تكون تشغيل أو إيقاف' end;
  elsif p_kind in ('text', 'text_long') then
    if v_type <> 'string' then return 'القيمة يجب أن تكون نصاً'; end if;
    return private.app_config_text_problem(p_value #>> '{}', p_kind = 'text_long', p_max_length, p_rules);
  elsif p_kind = 'json' then
    if v_items is null then return null; end if;
    if v_type <> 'array' then return 'القيمة يجب أن تكون قائمة'; end if;
    v_n := jsonb_array_length(p_value);
    if v_n < coalesce((p_rules ->> 'min_items')::integer, 0) or v_n > coalesce((p_rules ->> 'max_items')::integer, 50) then
      return 'عدد العناصر يجب أن يكون بين ' || coalesce((p_rules ->> 'min_items')::integer, 0) || ' و'
             || coalesce((p_rules ->> 'max_items')::integer, 50);
    end if;
    if coalesce((p_rules ->> 'unique')::boolean, false)
       and (select count(distinct e) from jsonb_array_elements(p_value) e) <> v_n then
      return 'في القائمة عناصر مكررة';
    end if;
    for v_item in select e from jsonb_array_elements(p_value) e loop
      if v_items = 'int' then
        if jsonb_typeof(v_item) <> 'number' or (v_item #>> '{}')::numeric <> trunc((v_item #>> '{}')::numeric) then
          return 'كل عنصر يجب أن يكون رقماً صحيحاً';
        end if;
        v_num := (v_item #>> '{}')::numeric;
        if (p_min is not null and v_num < p_min) or (p_max is not null and v_num > p_max) then
          return 'كل رقم يجب أن يكون ' || v_range;
        end if;
        if coalesce((p_rules ->> 'ascending')::boolean, false) and v_prev is not null and v_num <= v_prev then
          return 'الأرقام يجب أن تكون تصاعدية';
        end if;
        v_prev := v_num;
      elsif v_items = 'text' then
        if jsonb_typeof(v_item) <> 'string' then return 'كل عنصر يجب أن يكون نصاً'; end if;
        v_msg := private.app_config_text_problem(v_item #>> '{}', false, p_max_length, '{"min_length": 1}'::jsonb);
        if v_msg is not null then return v_msg; end if;
      elsif v_items = 'uuid' then
        if jsonb_typeof(v_item) <> 'string' or (v_item #>> '{}') !~ v_uuid then return 'معرّف غير صالح'; end if;
      elsif v_items = 'branch_head' then
        if jsonb_typeof(v_item) <> 'object' then return 'كل فرع يجب أن يكون {"name": …, "id": …}'; end if;
        for v_key in select jsonb_object_keys(v_item) loop
          if v_key not in ('id', 'name') then return 'مفتاح غير معروف في الفرع: ' || v_key; end if;
        end loop;
        if coalesce(jsonb_typeof(v_item -> 'name'), '') <> 'string' then return 'اسم الفرع مطلوب'; end if;
        v_msg := private.app_config_text_problem(v_item ->> 'name', false, p_max_length, '{"min_length": 1}'::jsonb);
        if v_msg is not null then return v_msg; end if;
        if coalesce(jsonb_typeof(v_item -> 'id'), 'null') <> 'null'
           and (jsonb_typeof(v_item -> 'id') <> 'string' or (v_item ->> 'id') !~ v_uuid) then
          return 'معرّف الفرع غير صالح';
        end if;
      else
        return 'نوع عناصر غير معروف';
      end if;
    end loop;
    return null;
  end if;
  return 'نوع غير معروف';
end;
$function$
`);
await db.exec(`CREATE OR REPLACE FUNCTION private.app_config_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_msg text;
begin
  v_msg := private.app_config_problem(new.kind, new.default_value, new.min_value, new.max_value, new.max_length, new.rules);
  if v_msg is not null then
    raise exception 'الافتراضي لـ %: %', new.key, v_msg using errcode = '22023', hint = 'bad_value';
  end if;
  v_msg := private.app_config_problem(new.kind, new.value, new.min_value, new.max_value, new.max_length, new.rules);
  if v_msg is not null then
    raise exception '%', v_msg using errcode = '22023', hint = 'bad_value';
  end if;
  return new;
end;
$function$
`);
await db.exec(`CREATE OR REPLACE FUNCTION private.app_config_log()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if new.value is distinct from old.value then
    insert into public.app_config_history (key, old_value, new_value, changed_by, changed_by_name)
    values (new.key, old.value, new.value, public.current_profile_id(),
            (select coalesce(nullif(btrim(p.full_name), ''), nullif(btrim(p.first_name), ''))
               from public.profiles p where p.id = public.current_profile_id()));
  end if;
  return null;
end;
$function$
`);
await db.exec(`CREATE OR REPLACE FUNCTION public.set_app_config(p_key text, p_value jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  r     public.app_config%rowtype;
  v_new jsonb;
  v_msg text;
begin
  if coalesce(public.current_user_role(), '') <> 'owner' then
    raise exception 'تعديل إعدادات التطبيق للمالك فقط' using errcode = '42501', hint = 'not_allowed';
  end if;
  select * into r from public.app_config c where c.key = p_key for update;
  if not found then
    raise exception 'إعداد غير معروف: %', coalesce(p_key, '') using errcode = 'P0002', hint = 'unknown_key';
  end if;
  v_new := case when p_value is null or jsonb_typeof(p_value) = 'null' then r.default_value else p_value end;
  v_msg := private.app_config_problem(r.kind, v_new, r.min_value, r.max_value, r.max_length, r.rules);
  if v_msg is not null then
    raise exception '%', v_msg using errcode = '22023', hint = 'bad_value';
  end if;
  update public.app_config c
     set value = v_new, updated_at = now(),
         updated_by = (select p.id from public.profiles p where p.id = public.current_profile_id())
   where c.key = p_key
  returning * into r;
  return jsonb_build_object('key', r.key, 'value', r.value, 'default_value', r.default_value,
                            'is_default', r.value = r.default_value, 'updated_at', r.updated_at, 'updated_by', r.updated_by);
end;
$function$
`);
await db.exec(`CREATE OR REPLACE FUNCTION public.app_config()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_role   text := coalesce(public.current_user_role(), '');
  v_member boolean := v_role in ('owner', 'admin', 'monitor', 'supervisor', 'member');
  v_values jsonb;
  v_at     timestamptz;
  v_wait   integer;
  v_open   boolean;
  v_set_at timestamptz;
  v_out    jsonb;
begin
  select coalesce(jsonb_object_agg(c.key, c.value), '{}'::jsonb), max(c.updated_at)
    into v_values, v_at
    from public.app_config c
   where v_member or c.is_public;
  select a.sms_wait_seconds, a.allow_new_registrations, a.updated_at
    into v_wait, v_open, v_set_at
    from public.app_settings a order by a.updated_at desc limit 1;
  v_out := jsonb_build_object(
    'values', v_values || jsonb_build_object('sms_wait_seconds', coalesce(v_wait, 60),
                                             'allow_new_registrations', coalesce(v_open, true)),
    'scope', case when v_member then 'member' else 'public' end,
    'updated_at', greatest(v_at, v_set_at));
  if v_role = 'owner' then
    v_out := v_out || jsonb_build_object(
      'can_edit', v_role = 'owner',
      'categories', jsonb_build_array(
        jsonb_build_object('key', 'members', 'label_ar', 'الأعضاء', 'sort', 10),
        jsonb_build_object('key', 'news', 'label_ar', 'الأخبار', 'sort', 20),
        jsonb_build_object('key', 'tree', 'label_ar', 'الشجرة', 'sort', 30),
        jsonb_build_object('key', 'notifications', 'label_ar', 'الإشعارات والإعلانات', 'sort', 40),
        jsonb_build_object('key', 'approvals', 'label_ar', 'الموافقات', 'sort', 50),
        jsonb_build_object('key', 'deaths', 'label_ar', 'الوفيات', 'sort', 60),
        jsonb_build_object('key', 'sms', 'label_ar', 'رسائل الدخول', 'sort', 70),
        jsonb_build_object('key', 'links', 'label_ar', 'الروابط', 'sort', 80),
        jsonb_build_object('key', 'general', 'label_ar', 'عام', 'sort', 90)),
      'meta', (select coalesce(jsonb_object_agg(c.key, jsonb_build_object(
                 'kind', c.kind, 'label_ar', c.label_ar, 'help_ar', c.help_ar, 'category', c.category,
                 'sort', c.sort, 'min', c.min_value, 'max', c.max_value, 'max_length', c.max_length,
                 'rules', c.rules, 'is_public', c.is_public, 'default', c.default_value,
                 'is_default', c.value = c.default_value, 'updated_at', c.updated_at, 'updated_by', c.updated_by,
                 'updated_by_name', coalesce(nullif(btrim(p.full_name), ''), nullif(btrim(p.first_name), '')))), '{}'::jsonb)
                 from public.app_config c
                 left join public.profiles p on p.id = c.updated_by));
  end if;
  return v_out;
end;
$function$
`);
await db.exec(`
create trigger trg_app_config_guard before insert or update on public.app_config for each row execute function private.app_config_guard();
create trigger trg_app_config_log after update on public.app_config for each row execute function private.app_config_log();
alter table public.app_config enable row level security;
alter table public.app_config_history enable row level security;
revoke all on public.app_config, public.app_config_history from public, anon, authenticated;
grant usage on schema public, auth to authenticated, anon;
grant execute on function public.app_config(), public.set_app_config(text, jsonb), public.current_user_role() to authenticated, anon;
insert into public.profiles values ('${O}', 'owner', 'active', 'حسن المالك', 'حسن'), ('${A}', 'admin', 'active', 'بدر', 'بدر'),
  ('${MON}', 'monitor', 'active', 'علي', 'علي'), ('${S}', 'supervisor', 'active', 'سعد', 'سعد'), ('${M}', 'member', 'active', 'أحمد', 'أحمد');
insert into public.app_config (key, value, default_value, kind, min_value, max_value, category, label_ar, sort) values
  ('death_announce_window_days', '30', '30', 'int', 7, 90, 'deaths', 'مدة إعلان الوفاة', 10);
`);

const LIVE = {
  'private.app_config_text_problem(text,boolean,integer,jsonb)': '7e1d208311c109e2355ad1bf09a1839d',
  'private.app_config_problem(text,jsonb,numeric,numeric,integer,jsonb)': '4e76bcfa35a0477c67e116e875589b39',
  'private.app_config_guard()': '1968bdd2a0110aec0f5705e4dad374c3',
  'private.app_config_log()': 'ebad68cdd61332e119b59e56149e9406',
  'set_app_config(text,jsonb)': '4d7a97a469a816c9423d1e32b7df534d',
  'app_config()': '2accad570c8136787b96603415b8ae65',
};
const md5s = async () => Object.fromEntries((await db.query(`select p.oid::regprocedure::text s, md5(pg_get_functiondef(p.oid)) m
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('public', 'private')`)).rows.map(r => [r.s, r.m]));
const as = async (who, sql, params) => {
  await db.exec(`select set_config('request.jwt.claim.sub', '${who ?? ''}', false); set role ${who ? 'authenticated' : 'anon'};`);
  try { return await db.query(sql, params); } finally { await db.exec(`reset role; select set_config('request.jwt.claim.sub', '', false);`); }
};
const cfg = async who => (await as(who, `select public.app_config() c`)).rows[0].c;
const set = async (who, key, value) => {
  try { return { ok: true, r: (await as(who, `select public.set_app_config($1, $2::jsonb) r`, [key, value])).rows[0].r }; }
  catch (e) { return { ok: false, code: e.code, hint: e.hint, msg: e.message }; }
};


const BEFORE = await md5s();
for (const [sig, m] of Object.entries(LIVE)) ok(BEFORE[sig] === m, `النسخة المحلية = الحية حرفياً: ${sig}`, BEFORE[sig]);

const q = async (who, sql, params) => {
  try { return { ok: true, r: (await as(who, sql, params)).rows[0]?.r }; }
  catch (e) { return { ok: false, code: e.code, hint: e.hint, msg: e.message }; }
};
const policy = (who, platform, build) => q(who, `select public.app_update_policy($1, $2) r`, [platform, build]);
const save = (who, p) => q(who, `select public.set_update_policy($1::jsonb) r`, [JSON.stringify(p)]);

// أجهزة قبل الترحيل (التسجيل الحالي بلا أعمدة النسخة)
await db.exec(`insert into public.device_tokens (member_id, device_id, platform, device_name, updated_at) values
  ('${M}', 'm-iphone', 'ios', 'iPhone 15', now() - interval '1 day'),
  ('${M}', 'm-ipad', 'ipados', 'iPad', now() - interval '2 days'),
  ('${A}', 'a-android', 'android', 'Galaxy', now() - interval '3 days'),
  ('${MON}', 'mon-iphone', 'ios', 'iPhone 12', now() - interval '40 days'),
  ('${S}', 's-iphone', 'ios', 'iPhone 13', now()),
  ('${O}', 'o-iphone', 'ios', 'iPhone 17', now());`);

// ══════════ الترحيل ══════════
await db.exec(MIG);
const keys = (await db.query(`select key, value, default_value, kind, is_public from public.app_config where key ~ '(update|latest)' order by key`)).rows;
ok(keys.length === 14, '١٤ مفتاحاً أُضيفت', keys.length);
ok(keys.every(k => k.is_public === false), 'كلها للمسجّلين فقط');
const fm = keys.find(k => k.key === 'update_force_message');
ok(fm.value === 'رسالة المالك القديمة' && fm.default_value !== fm.value, 'رسالة المالك السابقة انتقلت لشاشة الإجبار');
ok((await db.query(`select column_name from information_schema.columns where table_name = 'device_tokens' and column_name in ('app_build','app_version','build_seen_at')`)).rows.length === 3,
  'أعمدة النسخة على الأجهزة');
const AFTER = await md5s();
ok(Object.keys(BEFORE).every(s => AFTER[s] === BEFORE[s]), 'لا دالة حيّة تغيّرت');
for (const who of [O, A, M]) ok((await cfg(who)).values.update_snooze_days === 2, `المفاتيح تصل عبر app_config() (${who.slice(-1)})`);
ok((await cfg(null)).values.update_mode_ios === undefined, 'غير المسجّل لا يراها');

// ══════════ الافتراضي = لا شيء (اليوم) ══════════
let r = await policy(M, 'ios', 49);
ok(r.ok && r.r.state === 'none' && r.r.latest_build === 0, 'بلا ضبط: لا مربّع ولا قفل', JSON.stringify(r));
ok((await policy(null, 'ios', 49)).ok === false, 'غير المسجّل لا يستدعيها');
ok((await policy(M, 'windows', 49)).code === '22023', 'منصة غير معروفة مرفوضة');
// الحد الأدنى القديم يعمل كما هو
await db.exec(`update public.app_settings set ios_min_build = 48`);
ok((await policy(M, 'ios', 47)).r.state === 'forced' && (await policy(M, 'ios', 47)).r.reason === 'min_build', 'تحت الحد الأدنى = إجباري (كما اليوم)');
ok((await policy(M, 'ios', 48)).r.state === 'none', 'عند الحد = لا شيء');
ok((await policy(O, 'ios', 1)).r.state === 'optional' && (await policy(O, 'ios', 1)).r.exempt === true, 'المالك تحت الحد لا ينقفل (مربّع بـ«لاحقاً»)');
await db.exec(`update public.app_settings set ios_min_build = 0`);

// ══════════ الحفظ: المالك وحده ══════════
r = await save(A, { ios: { latest_build: 50 } });
ok(!r.ok && r.code === '42501', 'المدير لا يحفظ (42501)');
ok(!(await q(A, `select public.update_policy_admin() r`)).ok, 'المدير لا يقرأ صفحة الإعداد');
r = await save(O, { ios: { latest_build: 50, latest_version: '1.0.1', min_build: 49, mode: 'optional' },
                    whats_new: '  إضافة الأبناء مباشرة من «عائلتي»\r\n\nشجرة النساء: ترتيب الزوجات  \n بحث أدق بالأسماء',
                    snooze_days: 3 });
ok(r.ok, 'المالك يحفظ', JSON.stringify(r));
ok(r.r.ios.latest_build === 50 && r.r.ios.min_build === 49 && r.r.ios.latest_version === '1.0.1', 'القيم رجعت محفوظة');
ok(r.r.whats_new === 'إضافة الأبناء مباشرة من «عائلتي»\nشجرة النساء: ترتيب الزوجات\nبحث أدق بالأسماء', '«ما الجديد» أسطر نظيفة', JSON.stringify(r.r.whats_new));
ok((await db.query(`select ios_min_build from public.app_settings`)).rows[0].ios_min_build === 49, 'الحد الأدنى في app_settings (تقرؤه النسخ الحالية)');
ok((await db.query(`select count(*)::int n from public.app_config_history where key = 'ios_latest_build'`)).rows[0].n === 1, 'التغيير مسجّل في السجل');
ok(r.r.android.latest_build === 0 && r.r.android.min_build === 2, 'الأندرويد لم يُلمس');

// ══════════ اختياري ══════════
r = await policy(M, 'ios', 49);
ok(r.r.state === 'optional' && r.r.can_snooze && r.r.snooze_days === 3, 'أقدم من الأخيرة = اختياري بـ«لاحقاً» بعد ٣ أيام');
ok(JSON.stringify(r.r.whats_new) === JSON.stringify(['إضافة الأبناء مباشرة من «عائلتي»', 'شجرة النساء: ترتيب الزوجات', 'بحث أدق بالأسماء']), '«ما الجديد» قائمة');
ok(r.r.latest_version === '1.0.1' && r.r.force_title === 'حدّث التطبيق', 'اسم النسخة والعنوان');
ok((await policy(M, 'ipados', 50)).r.state === 'none', 'آخر نسخة (الآيباد = آيفون) = لا شيء');
ok((await policy(M, 'ios', 48)).r.state === 'forced', 'تحت الحد الأدنى = إجباري ولو الوضع اختياري');

// ══════════ إجباري من تاريخ ══════════
r = await save(O, { ios: { mode: 'scheduled' } });
ok(!r.ok && r.hint === 'deadline_required', '«من تاريخ» بلا موعد مرفوض');
r = await save(O, { ios: { min_build: 51 } });
ok(!r.ok && r.hint === 'min_above_latest', 'الأدنى أكبر من الأخيرة مرفوض');
r = await save(O, { ios: { mode: 'scheduled', deadline: 'غداً' } });
ok(!r.ok && r.hint === 'bad_deadline', 'موعد غير صالح مرفوض');
const in5 = (await db.query(`select (now() + interval '5 days 14 hours') t`)).rows[0].t.toISOString();
r = await save(O, { ios: { mode: 'scheduled', deadline: in5 } });
ok(r.ok && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/.test(r.r.ios.deadline), 'الموعد يُحفظ بوقت عالمي موحّد', r.r?.ios?.deadline);
r = await policy(M, 'ios', 49);
ok(r.r.state === 'scheduled' && r.r.can_snooze === true && !!r.r.deadline, 'قبل الموعد: المربّع بعدّ و«لاحقاً»');
await save(O, { ios: { deadline: (await db.query(`select (now() + interval '20 hours') t`)).rows[0].t.toISOString() } });
r = await policy(M, 'ios', 49);
ok(r.r.state === 'scheduled' && r.r.can_snooze === false, 'آخر يوم: «لاحقاً» تختفي');
ok((await policy(O, 'ios', 49)).r.can_snooze === true, 'المالك آخر يوم: «لاحقاً» باقية');
await save(O, { ios: { deadline: (await db.query(`select (now() - interval '1 minute') t`)).rows[0].t.toISOString() } });
r = await policy(M, 'ios', 49);
ok(r.r.state === 'forced' && r.r.reason === 'deadline', 'بعد الموعد = إجباري');
ok((await policy(O, 'ios', 49)).r.state === 'optional', 'المالك بعد الموعد لا ينقفل');
ok((await policy(M, 'ios', 50)).r.state === 'none', 'من حدّث بعد الموعد = لا شيء');

// ══════════ إجباري الحين ══════════
r = await save(O, { ios: { mode: 'forced' } });
ok(r.ok && r.r.ios.deadline !== null, 'إجباري الحين (الموعد يبقى محفوظاً)');
ok((await policy(M, 'ios', 49)).r.reason === 'forced_now', 'أقدم من الأخيرة = إجباري الحين');
r = await save(O, { ios: { mode: 'optional', deadline: '' } });
ok(r.ok && r.r.ios.deadline === null && (await policy(M, 'ios', 49)).r.state === 'optional', 'رجوع لاختياري ومسح الموعد');
ok(!(await save(O, { ios: { mode: 'later' } })).ok, 'نوع غير معروف مرفوض');
ok(!(await save(O, { ios: { foo: 1 } })).ok && !(await save(O, { foo: 1 })).ok, 'مفاتيح غير معروفة مرفوضة');
ok(!(await save(O, { ios: { update_url: 'http://x' } })).ok, 'الرابط لازم https');
r = await save(O, { ios: { update_url: 'https://apps.apple.com/app/id1' }, android: { latest_build: 48, min_build: 46, mode: 'optional' } });
ok(r.ok && r.r.ios.update_url === 'https://apps.apple.com/app/id1' && r.r.android.latest_build === 48, 'الرابط والأندرويد يُحفظان');
ok(r.r.legacy_android.force_update === false, 'الطريقة القديمة للأندرويد كما هي (لا تُلمس)');
ok((await policy(A, 'android', 47)).r.state === 'optional' && (await policy(A, 'android', 45)).r.state === 'forced', 'الأندرويد بقيمه هو');
// النصوص: فارغ = الافتراضي، والطويل مرفوض بالفحص
r = await save(O, { force_title: '  ', force_message: 'حدّث الحين', reminder_title: 'تذكير' });
ok(r.ok && r.r.force_title === 'حدّث التطبيق' && r.r.force_message === 'حدّث الحين' && r.r.reminder_title === 'تذكير', 'النصوص تُحفظ والفارغ = الافتراضي');
ok(!(await save(O, { force_title: 'x'.repeat(61) })).ok, 'العنوان الطويل مرفوض');
ok(!(await save(O, { snooze_days: 0 })).ok && !(await save(O, { snooze_days: 31 })).ok, '«لاحقاً» بين ١ و٣٠ يوماً');
ok((await set(O, 'update_mode_ios', '"soon"')).ok === false, 'المحرّر العام يرفض نوعاً غير معروف أيضاً');
ok((await set(A, 'update_whats_new', '"x"')).ok === false, 'المدير لا يغيّر النصوص من المحرّر العام');

// ══════════ الجهاز يبلّغ نسخته ══════════
r = await q(M, `select public.report_app_build('m-iphone', 49, '1.0.0') r`);
ok(r.ok && r.r === true, 'العضو يبلّغ نسخة جهازه');
r = await q(M, `select public.report_app_build('a-android', 1, 'x') r`);
ok(r.ok && r.r === false, 'لا يبلّغ عن جهاز غيره');
ok((await db.query(`select app_build from public.device_tokens where device_id = 'a-android'`)).rows[0].app_build === null, 'جهاز المدير لم يتغيّر');
ok(!(await q(M, `select public.report_app_build('m-iphone', -1, null) r`)).ok, 'رقم سالب مرفوض');
ok((await q(null, `select public.report_app_build('m-iphone', 50, null) r`)).ok === false, 'غير المسجّل لا يبلّغ');
await q(S, `select public.report_app_build('s-iphone', 50, '1.0.1') r`);
await q(O, `select public.report_app_build('o-iphone', 50, '1.0.1') r`);
await q(A, `select public.report_app_build('a-android', 46, '1.0.0') r`);
const seen = (await db.query(`select build_seen_at from public.device_tokens where device_id = 'm-iphone'`)).rows[0].build_seen_at;
ok(seen && Math.abs(Date.now() - new Date(seen).getTime()) < 60000, 'وقت التبليغ من السيرفر');
// تحديث الجهاز العادي (upsert التسجيل) يبقى يعمل بلا الأعمدة
r = await q(M, `insert into public.device_tokens (member_id, device_id, platform, token) values ('${M}', 'm-iphone', 'ios', 'tok')
  on conflict (member_id, device_id) do update set token = excluded.token, updated_at = now() returning app_build r`);
ok(r.ok && r.r === 49, 'تسجيل الجهاز (upsert) كما هو، والنسخة المبلّغة باقية');

// ══════════ «النسخ عند الأعضاء» ══════════
ok(!(await q(A, `select public.app_build_overview(30) r`)).ok, 'المدير لا يرى «النسخ عند الأعضاء»');
r = await q(O, `select public.app_build_overview(30) r`);
ok(r.ok, 'المالك يراها', JSON.stringify(r));
const ov = r.r;
ok(ov.ios.latest_build === 50 && ov.ios.total === 4 && ov.ios.on_latest === 2 && ov.ios.older === 1 && ov.ios.unknown === 1,
  'الآيفون: ٤ أجهزة آخر ٣٠ يوماً (الآيباد معها، والقديم ٤٠ يوماً خارجها): ٢ على الأخيرة، ١ أقدم، ١ لم يبلّغ', JSON.stringify(ov.ios));
ok(ov.android.latest_build === 48 && ov.android.older === 1 && ov.android.on_latest === 0, 'الأندرويد: ١ أقدم من ٤٨');
ok(JSON.stringify(ov.ios.builds) === JSON.stringify([{ build: 50, count: 2 }, { build: 49, count: 1 }]), 'توزيع النسخ');
const devs = ov.devices.map(d => `${d.platform}:${d.build ?? '-'}:${d.name}`).sort();
ok(JSON.stringify(devs) === JSON.stringify(['android:46:بدر', 'ios:-:أحمد', 'ios:49:أحمد']), 'قائمة الأقدم (ومن لم يبلّغ)', JSON.stringify(devs));
ok(ov.devices.every(d => d.member_id && d.last_seen), 'كل صفّ بمعرّف العضو وآخر ظهور');
r = await q(O, `select public.app_build_overview(60) r`);
ok(r.r.ios.total === 5, '٦٠ يوماً تشمل الجهاز الأقدم');

// ══════════ إعادة التطبيق والتراجع ══════════
await db.exec(MIG);
const again = (await q(O, `select public.update_policy_admin() r`)).r;
ok(again.ios.latest_build === 50 && again.force_message === 'حدّث الحين' && again.android.latest_build === 48, 'إعادة الترحيل لا تمسّ اختيار المالك');
await db.exec(RB);
ok((await db.query(`select count(*)::int n from public.app_config where key ~ '(update|latest)'`)).rows[0].n === 0, 'التراجع يحذف المفاتيح');
ok((await db.query(`select count(*)::int n from information_schema.columns where table_name = 'device_tokens' and column_name like 'app_%'`)).rows[0].n === 0, 'وأعمدة الأجهزة');
ok((await db.query(`select count(*)::int n from pg_proc where proname in ('app_update_policy','set_update_policy','report_app_build','app_build_overview','update_policy_admin','update_policy_values','update_policy_texts')`)).rows[0].n === 0, 'والدوال');
ok((await db.query(`select ios_min_build, ios_update_url from public.app_settings`)).rows[0].ios_update_url === 'https://apps.apple.com/app/id1', 'app_settings باقية');
const FINAL = await md5s();
ok(Object.keys(BEFORE).every(s => FINAL[s] === BEFORE[s]), 'الدوال الحية كما هي بعد التراجع');
ok((await db.query(`select count(*)::int n from public.device_tokens`)).rows[0].n === 6, 'الأجهزة باقية');

console.log(`\n${pass} نجح، ${fail} فشل`);
process.exit(fail ? 1 : 0);
