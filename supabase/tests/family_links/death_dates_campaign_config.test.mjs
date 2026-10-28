// تجربة 20261025110000_death_dates_campaign_config (مفتاحا «إدارة تواريخ الوفاة» في app_config) على قاعدة محلية معزولة —
// لا تلمس السيرفر. app_config وفحصه وسجلّه وset_app_config وapp_config() منسوخة حرفياً من الحي (md5 مطابقة).
// يثبت: البذرتان تمرّان فحص السيرفر، القيم تصل كل الإدارة (التطبيق يقرأ values.death_dates_campaign و…_until)، التعديل
// للمالك وحده بالقيم الصحيحة فقط، إعادة التطبيق لا تمسّ اختيار المالك، والتراجع يحذفهما.
// التشغيل: cd supabase/tests/family_links && node death_dates_campaign_config.test.mjs
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
process.on('unhandledRejection', e => { console.log('خطأ:', e.message, (e.query ?? '').slice(0, 300)); process.exit(2); });

const REPO = fileURLToPath(new URL('../../', import.meta.url));
const MIG = readFileSync(`${REPO}/migrations/20261025110000_death_dates_campaign_config.sql`, 'utf8');
const RB = readFileSync(`${REPO}/rollback/20261025110000_death_dates_campaign_config_rollback.sql`, 'utf8');
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
create table public.app_settings (id int primary key default 1, sms_wait_seconds int default 60,
  allow_new_registrations boolean default true, updated_at timestamptz default now());
insert into public.app_settings (id) values (1);
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
  if v_role in ('owner', 'admin') then
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
  'app_config()': '415ace6352adde583c73321cfeac2bd8',
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

// ══════════ الترحيل ══════════
await db.exec(MIG);
const keys = (await db.query(`select key, value, default_value, kind, category, is_public from public.app_config
  where key like 'death_dates_campaign%' order by key`)).rows;
ok(keys.length === 2, 'المفتاحان أُضيفا ومرّا فحص السيرفر');
ok(keys[0].key === 'death_dates_campaign' && keys[0].value === true && keys[0].default_value === true && keys[0].kind === 'bool',
  'death_dates_campaign: bool، افتراضي true (الحملة ظاهرة)');
ok(keys[1].key === 'death_dates_campaign_until' && keys[1].value === '' && keys[1].kind === 'text',
  'death_dates_campaign_until: نص فارغ = حتى تكتمل التواريخ');
ok(keys.every(k => k.category === 'deaths' && k.is_public === false), 'في «الوفيات» وليسا عامّين');
const AFTER = await md5s();
ok(Object.keys(BEFORE).every(s => AFTER[s] === BEFORE[s]), 'لا دالة تغيّرت');
for (const who of [O, A, MON, S, M]) {
  const v = (await cfg(who)).values;
  ok(v.death_dates_campaign === true && v.death_dates_campaign_until === '', `القيمتان تصلان (${who.slice(-1)})`);
}
ok((await cfg(null)).values.death_dates_campaign === undefined, 'غير المسجّل لا يراهما (ليسا عامّين)');
ok((await cfg(O)).meta.death_dates_campaign.label_ar.includes('إدارة تواريخ الوفاة'), 'الوصف العربي للمالك (meta)');

// ══════════ التعديل: المالك وحده، والقيم الصحيحة فقط ══════════
let r = await set(A, 'death_dates_campaign', 'false');
ok(!r.ok && r.code === '42501' && r.hint === 'not_allowed', 'المدير لا يوقف الحملة (42501 not_allowed)', JSON.stringify(r));
ok(!(await set(MON, 'death_dates_campaign_until', '"2026-11-30"')).ok, 'المراقب لا يحدّد آخر يوم');
r = await set(O, 'death_dates_campaign', 'false');
ok(r.ok && r.r.value === false, 'المالك يوقفها (false)');
ok((await cfg(MON)).values.death_dates_campaign === false, 'والإيقاف يصل المراقب فوراً (التطبيق يعرض «ذكرى الراحلين»)');
r = await set(O, 'death_dates_campaign_until', '"2026-11-30"');
ok(r.ok && r.r.value === '2026-11-30', 'المالك يحدّد آخر يوم 2026-11-30');
for (const [bad, why] of [['"30/11/2026"', 'صيغة أخرى'], ['"2026-13-01"', 'شهر ١٣'], ['"2026-11-30 "', 'مسافة'], ['true', 'ليس نصاً']]) {
  const x = await set(O, 'death_dates_campaign_until', bad);
  ok(!x.ok && x.hint === 'bad_value', `يُرفض آخر يوم ${bad} (${why})`, JSON.stringify(x));
}
const fmt = await set(O, 'death_dates_campaign_until', '"30/11/2026"');
ok(fmt.msg === 'التاريخ بصيغة 2026-11-30 أو فارغ', 'رسالة الرفض بالعربي من القاعدة', fmt.msg);
ok(!(await set(O, 'death_dates_campaign', '"no"')).ok, 'يُرفض غير المنطقي للإبراز');
ok((await set(O, 'death_dates_campaign_until', '""')).ok, 'الفارغ مقبول (بلا نهاية)');
r = await set(O, 'death_dates_campaign', 'null');
ok(r.ok && r.r.value === true && r.r.is_default === true, 'null يرجعها للافتراضي (ظاهرة)');
const hist = (await db.query(`select key, new_value, changed_by from public.app_config_history order by id`)).rows;
ok(hist.length === 4 && hist.every(h => h.changed_by === O), 'كل تغيير في السجل باسم المالك', JSON.stringify(hist));

// ══════════ إعادة التطبيق لا تمسّ اختيار المالك ══════════
await set(O, 'death_dates_campaign', 'false');
await db.exec(MIG);
ok((await cfg(A)).values.death_dates_campaign === false, 'إعادة الترحيل لا تُرجع الإيقاف (on conflict do nothing)');

// ══════════ التراجع ══════════
await db.exec(RB);
ok((await db.query(`select count(*)::int n from public.app_config where key like 'death_dates_campaign%'`)).rows[0].n === 0, 'التراجع: حُذف المفتاحان');
ok((await cfg(A)).values.death_dates_campaign === undefined && (await cfg(A)).values.death_announce_window_days === 30,
  'التراجع: لا مفتاحان (التطبيق يرجع لافتراضه) والباقي كما هو');
r = await set(O, 'death_dates_campaign', 'false');
ok(!r.ok && r.hint === 'unknown_key', 'التراجع: الحفظ يردّ unknown_key (التطبيق يعرض «يحتاج تحديث السيرفر»)');
ok((await db.query(`select count(*)::int n from public.app_config_history`)).rows[0].n === 5, 'السجل يبقى للأثر');
await db.exec(MIG);
ok((await cfg(MON)).values.death_dates_campaign === true, 'يُطبَّق من جديد بعد التراجع');

console.log(`\n${pass} نجح، ${fail} فشل`);
process.exit(fail ? 1 : 0);
