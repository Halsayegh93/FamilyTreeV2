-- إعدادات عامة من السيرفر: ٣١ قيمة مربوطة فعلياً بالتطبيق ودوال السيرفر.
-- المالك يعدّل عبر set_app_config، المدير يقرأ الوصف والسجل، والأعضاء يأخذون القيم المناسبة لنطاقهم.
-- الروابط عامة قبل الدخول؛ لا كتابة مباشرة من التطبيقات. كل قيمة تُفحص ويُسجّل تغييرها.
-- لم تُضمّن حدود تعديل الملف أو نسخة الموافقة على الشروط أو حدود الفئات العمرية والفروع: تبقى بأنظمتها الحالية.
-- التراجع: supabase/rollback/20261021110000_app_config_rollback.sql (تراجع عن قراءات السيرفر أولاً).
-- الاختبار: node supabase/tests/family_links/app_config.test.mjs

-- ═══ ١) الجدولان ═══
create table public.app_config (
  key           text primary key check (key ~ '^[a-z][a-z0-9_]{1,62}$'),
  value         jsonb not null,
  default_value jsonb not null,
  kind          text not null check (kind in ('int', 'bool', 'text', 'text_long', 'json')),
  min_value     numeric,
  max_value     numeric,
  max_length    integer check (max_length is null or max_length between 1 and 10000),
  category      text not null check (category in ('members', 'news', 'tree', 'notifications', 'approvals', 'deaths',
                                                  'sms', 'links', 'general')),
  label_ar      text not null check (btrim(label_ar) <> ''),
  help_ar       text,
  rules         jsonb not null default '{}'::jsonb check (jsonb_typeof(rules) = 'object'),
  is_public     boolean not null default false,
  sort          integer not null default 0,
  updated_at    timestamptz not null default now(),
  updated_by    uuid references public.profiles(id) on delete set null,
  constraint app_config_range_check check (min_value is null or max_value is null or min_value <= max_value)
);
comment on table public.app_config is
  'إعدادات التطبيق من السيرفر (مفتاح ← قيمة) — تقرؤها التطبيقات بـ app_config()/app_config_public() ويعدّلها المالك بـ set_app_config()';

create table public.app_config_history (
  id         bigserial primary key,
  key        text not null,
  old_value  jsonb,
  new_value  jsonb,
  changed_by uuid,
  changed_by_name text,
  changed_at timestamptz not null default now()
);
create index app_config_history_key_at on public.app_config_history (key, changed_at desc);
comment on table public.app_config_history is 'سجل تغييرات app_config — يقرؤه المالك والمدير';

alter table public.app_config enable row level security;
alter table public.app_config_history enable row level security;
revoke all on public.app_config, public.app_config_history from public, anon, authenticated, service_role;
revoke all on sequence public.app_config_history_id_seq from public, anon, authenticated, service_role;
grant select on public.app_config_history to authenticated;
create policy app_config_history_owner_admin_read on public.app_config_history for select to authenticated
  using (coalesce(public.current_user_role(), '') in ('owner', 'admin'));

-- ═══ ٢) فحص القيم (داخلي — مخطط private لا تصله التطبيقات) ═══
-- نص: الطول (الافتراضي ١ حرف على الأقل إلا إن قالت القاعدة min_length)، رموز التحكم (سطر جديد للنص الطويل فقط)،
-- placeholders (يجب وجودها؛ single_placeholders = مرة واحدة بالضبط)، pattern، bmp_only (لا رموز خارج BMP — طول رسالة
-- الرمز يتطابق بين SQL والدالة الطرفية)، sms_gsm (رسالة إنجليزية: ASCII بلا رموز الامتداد [ ] { } \ ^ ~ | `).
create function private.app_config_text_problem(p_text text, p_multiline boolean, p_max_length integer, p_rules jsonb)
returns text language plpgsql immutable set search_path = '' as $$
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
  if p_text ~ (case when p_multiline then '[\x01-\x09\x0b-\x1f\x7f]' else '[\x01-\x1f\x7f]' end) then
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
  if coalesce((p_rules ->> 'bmp_only')::boolean, false) and p_text ~ '[^\x01-￿]' then
    return 'النص فيه رموز (مثل الوجوه التعبيرية) لا تصلح لرسالة الرمز';
  end if;
  if coalesce((p_rules ->> 'sms_gsm')::boolean, false) and v_bare ~ '[^ -~]|[][{}\\^~|`]' then
    return 'الرسالة الإنجليزية: حروف وأرقام إنجليزية وعلامات بسيطة فقط';
  end if;
  return null;
end;
$$;

-- قيمة لنوع: int (صحيح ضمن المدى)، bool، text/text_long، json (قائمة بحسب rules.items: text/int/uuid/branch_head،
-- min_items/max_items، unique، ascending؛ بلا items = أي JSON غير null). يرجع null = سليمة، وإلا رسالة عربية للمالك.
create function private.app_config_problem(p_kind text, p_value jsonb, p_min numeric, p_max numeric,
  p_max_length integer, p_rules jsonb)
returns text language plpgsql immutable set search_path = '' as $$
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
$$;

-- كل إدراج/تعديل (من set_app_config أو صيانة SQL) يُفحص: القيمة والافتراضي
create function private.app_config_guard() returns trigger
language plpgsql set search_path = '' as $$
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
$$;
create trigger trg_app_config_guard before insert or update on public.app_config
  for each row execute function private.app_config_guard();

-- السجل: كل تغيير في value (المالك من التطبيق، أو صيانة SQL ← changed_by فارغ)
create function private.app_config_log() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.value is distinct from old.value then
    insert into public.app_config_history (key, old_value, new_value, changed_by, changed_by_name)
    values (new.key, old.value, new.value, public.current_profile_id(),
            (select coalesce(nullif(btrim(p.full_name), ''), nullif(btrim(p.first_name), ''))
               from public.profiles p where p.id = public.current_profile_id()));
  end if;
  return null;
end;
$$;
create trigger trg_app_config_log after update on public.app_config
  for each row execute function private.app_config_log();

revoke all on function private.app_config_text_problem(text, boolean, integer, jsonb) from public, anon, authenticated, service_role;
revoke all on function private.app_config_problem(text, jsonb, numeric, numeric, integer, jsonb) from public, anon, authenticated, service_role;
revoke all on function private.app_config_guard() from public, anon, authenticated, service_role;
revoke all on function private.app_config_log() from public, anon, authenticated, service_role;

-- ═══ ٣) قراءة دوال السيرفر (بلا تنفيذ للتطبيقات) — المفتاح غائب أو نوعه مختلف ← الاحتياطي ═══
create function public.config_int(p_key text, p_fallback integer) returns integer
language sql stable security definer set search_path = '' as $$
  select coalesce((select case when jsonb_typeof(c.value) = 'number'
                                and (c.value #>> '{}')::numeric = trunc((c.value #>> '{}')::numeric)
                                and abs((c.value #>> '{}')::numeric) <= 2147483647
                               then (c.value #>> '{}')::numeric::integer end
                     from public.app_config c where c.key = p_key), p_fallback);
$$;
create function public.config_text(p_key text, p_fallback text) returns text
language sql stable security definer set search_path = '' as $$
  select coalesce((select case when jsonb_typeof(c.value) = 'string' then c.value #>> '{}' end
                     from public.app_config c where c.key = p_key), p_fallback);
$$;
create function public.config_bool(p_key text, p_fallback boolean) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select case when jsonb_typeof(c.value) = 'boolean' then (c.value #>> '{}')::boolean end
                     from public.app_config c where c.key = p_key), p_fallback);
$$;
create function public.config_json(p_key text, p_fallback jsonb) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce((select case when jsonb_typeof(c.value) <> 'null' then c.value end
                     from public.app_config c where c.key = p_key), p_fallback);
$$;
revoke all on function public.config_int(text, integer) from public, anon, authenticated, service_role;
revoke all on function public.config_text(text, text) from public, anon, authenticated, service_role;
revoke all on function public.config_bool(text, boolean) from public, anon, authenticated, service_role;
revoke all on function public.config_json(text, jsonb) from public, anon, authenticated, service_role;

-- ═══ ٤) القراءة للتطبيقات ═══
create function public.app_config() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
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
$$;

create function public.app_config_public() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_values jsonb;
  v_at     timestamptz;
  v_wait   integer;
  v_open   boolean;
  v_set_at timestamptz;
begin
  select coalesce(jsonb_object_agg(c.key, c.value), '{}'::jsonb), max(c.updated_at)
    into v_values, v_at
    from public.app_config c where c.is_public;
  select a.sms_wait_seconds, a.allow_new_registrations, a.updated_at
    into v_wait, v_open, v_set_at
    from public.app_settings a order by a.updated_at desc limit 1;
  return jsonb_build_object(
    'values', v_values || jsonb_build_object('sms_wait_seconds', coalesce(v_wait, 60),
                                             'allow_new_registrations', coalesce(v_open, true)),
    'scope', 'public',
    'updated_at', greatest(v_at, v_set_at));
end;
$$;

-- ═══ ٥) التعديل (المالك فقط) ═══
create function public.set_app_config(p_key text, p_value jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
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
$$;

revoke all on function public.app_config() from public, anon, authenticated, service_role;
grant execute on function public.app_config() to authenticated;
revoke all on function public.app_config_public() from public, anon, authenticated, service_role;
grant execute on function public.app_config_public() to anon, authenticated;
revoke all on function public.set_app_config(text, jsonb) from public, anon, authenticated, service_role;
grant execute on function public.set_app_config(text, jsonb) to authenticated;

-- ═══ ٦) البذور — القيمة الحالية في التطبيقين/السيرفر = الافتراضي (لا تغيير في السلوك) ═══
insert into public.app_config (key, kind, value, default_value, min_value, max_value, max_length, category,
                               label_ar, help_ar, rules, is_public, sort)
select v.key, v.kind, v.def, v.def, v.min_value, v.max_value, v.max_length, v.category, v.label_ar, v.help_ar,
       v.rules::jsonb, v.is_public, v.sort
from (values
  -- ── الأعضاء ──
  ('living_check_old_birth_year', 'int', '1940'::jsonb, 1850::numeric, 2010::numeric, null::integer, 'members',
   'مراجعة الأحياء: مواليد قبل سنة',
   'من وُلد قبل هذه السنة يظهر في قسم «مواليد قبل …» في مراجعة الأحياء.',
   '{}', false, 40),
  ('living_check_median_year', 'int', '1960', 1850, 2010, null, 'members',
   'مراجعة الأحياء: الجيل القديم قبل سنة',
   'الجيل يُعدّ قديماً إذا كان وسط سنوات ميلاده المعروفة قبل هذه السنة، فيُراجَع أحياؤه.',
   '{}', false, 50),
  ('living_check_min_births', 'int', '3', 1, 20, null, 'members',
   'مراجعة الأحياء: أقل عدد مواليد معروفة',
   'أقل عدد تواريخ ميلاد معروفة في الجيل حتى يُحكم عليه بأنه قديم.',
   '{}', false, 60),
  ('activity_heartbeat_seconds', 'int', '60', 30, 600, null, 'members',
   'تحديث «نشط الآن» كل (ثانية)',
   'كل كم ثانية يبلّغ التطبيق أن العضو ما زال يستخدمه (يظهر «نشط الآن» لمن نشط خلال آخر ٥ دقائق).',
   '{}', false, 80),
  -- ── الأخبار ──
  ('news_max_photos', 'int', '5', 1, 10, null, 'news',
   'أقصى عدد صور في الخبر',
   'كم صورة يقدر العضو يرفق مع الخبر الواحد عند الإضافة والتعديل.',
   '{}', false, 10),
  ('report_review_hours', 'int', '24', 1, 168, null, 'news',
   'مدة مراجعة البلاغ (ساعات)',
   'المدة التي يُوعد بها العضو لمراجعة بلاغه — تظهر في رسالة الشكر والإشعار وشروط الاستخدام.',
   '{}', false, 20),
  -- ── الشجرة ──
  ('announce_preset_titles', 'json',
   '["عائلة المحمدعلي", "إعلان من الإدارة", "تذكير", "دعوة", "تهنئة", "تنبيه مهم"]',
   null, null, 60, 'notifications',
   'العناوين الجاهزة للإعلان',
   'قائمة العناوين في «إشعار للأعضاء». أولها هو العنوان حين يُترك فارغاً.',
   '{"items": "text", "min_items": 1, "max_items": 12, "unique": true}', false, 10),
  ('notify_join_approved_title', 'text', '"تم قبول طلبك"', null, null, 60, 'notifications',
   'إشعار قبول الانضمام: العنوان', 'يصل العضو حين تقبل الإدارة انضمامه.', '{}', false, 20),
  ('notify_join_approved_body', 'text', '"وافقت الإدارة على انضمامك — مرحباً في عائلة المحمدعلي"', null, null, 200,
   'notifications',
   'إشعار قبول الانضمام: النص', 'يقبل {name} لاسم العضو إن أردت.', '{}', false, 30),
  ('notify_news_like_title', 'text', '"إعجاب جديد"', null, null, 60, 'notifications',
   'إشعار الإعجاب: العنوان', 'يصل صاحب الخبر حين يعجب أحد بخبره.', '{}', false, 40),
  ('notify_news_like_body', 'text', '"{name} أعجب بمنشورك"', null, null, 200, 'notifications',
   'إشعار الإعجاب: النص', '{name} = اسم من أعجب.', '{"placeholders": ["{name}"]}', false, 50),
  ('notify_news_like_admin_body', 'text', '"الإدارة أعجبت بمنشورك"', null, null, 200, 'notifications',
   'إشعار الإعجاب من الإدارة', 'حين يعجب أحد أعضاء الإدارة بخبر عضو عادي يظهر باسم «الإدارة».', '{}', false, 60),
  ('notify_news_comment_title', 'text', '"تعليق جديد"', null, null, 60, 'notifications',
   'إشعار التعليق: العنوان', 'يصل صاحب الخبر حين يعلّق أحد على خبره.', '{}', false, 70),
  ('notify_news_comment_body', 'text', '"{name} علّق على منشورك"', null, null, 200, 'notifications',
   'إشعار التعليق: النص', '{name} = اسم من علّق.', '{"placeholders": ["{name}"]}', false, 80),
  ('notify_news_comment_admin_body', 'text', '"الإدارة علّقت على منشورك"', null, null, 200, 'notifications',
   'إشعار التعليق من الإدارة', 'حين يعلّق أحد أعضاء الإدارة على خبر عضو عادي يظهر باسم «الإدارة».', '{}', false, 90),
  -- ── الموافقات ──
  ('approvals_info_hours', 'int', '48', 1, 168, null, 'approvals',
   'مهلة رد العضو على «طلب معلومات» (ساعات)',
   'بعدها يُذكَّر صاحب الطلب ويُعدّ الطلب متأخراً في التقرير.',
   '{}', false, 10),
  -- ── الوفيات ──
  ('death_announce_window_days', 'int', '30', 7, 90, null, 'deaths',
   'مدة إعلان الوفاة (أيام)',
   'يُسمح بإعلان الوفاة إذا كانت خلال هذه الأيام بتوقيت الكويت (أو سُجّلت خلالها إن لم يُعرف تاريخها). تنبيه «وفاة لم يُعلن عنها» له إعداده الخاص.',
   '{}', false, 10),
  ('death_announce_template_male', 'text_long',
   to_jsonb(E'انتقل إلى رحمة الله تعالى {name}\nتغمّده الله بواسع رحمته وأسكنه فسيح جناته\nإنا لله وإنا إليه راجعون'::text),
   null, null, 600, 'deaths',
   'نص إعلان الوفاة (رجل)', 'النص الجاهز في مربّع الإعلان. {name} = اسم المتوفى.',
   '{"placeholders": ["{name}"]}', false, 20),
  ('death_announce_template_female', 'text_long',
   to_jsonb(E'انتقلت إلى رحمة الله تعالى {name}\nتغمّدها الله بواسع رحمته وأسكنها فسيح جناته\nإنا لله وإنا إليه راجعون'::text),
   null, null, 600, 'deaths',
   'نص إعلان الوفاة (امرأة)', 'النص الجاهز في مربّع الإعلان. {name} = اسم المتوفاة.',
   '{"placeholders": ["{name}"]}', false, 30),
  -- ── رسائل الدخول ──
  ('sms_suspicious_per_hour', 'int', '5', 2, 50, null, 'sms',
   'محاولات الدخول المريبة (في الساعة)',
   'إذا طلب رقم رمز الدخول هذا العدد أو أكثر خلال ساعة يُعدّ مريباً ويُنبَّه المالك والمدراء.',
   '{}', false, 10),
  ('sms_otp_template', 'text', '"عائلة المحمدعلي: رمز الدخول {code}. لا تشاركه مع أحد."', null, null, 70, 'sms',
   'نص رسالة رمز الدخول',
   'يجب أن يحتوي {code} مرة واحدة واسم العائلة (شرط KWT SMS)، و٧٠ حرفاً كحد أقصى حتى تبقى رسالة واحدة بنقطة واحدة.',
   '{"placeholders": ["{code}"], "single_placeholders": true, "bmp_only": true}', false, 20),
  ('sms_otp_template_en', 'text', '"Your Al-Mohammadali Family app login code is {code}. Do not share this code."',
   null, null, 160, 'sms',
   'نص رسالة الرمز بالإنجليزي',
   'يُستعمل فقط إذا ضُبطت الدالة على الإنجليزي. حروف إنجليزية فقط، و{code} مرة واحدة.',
   '{"placeholders": ["{code}"], "single_placeholders": true, "sms_gsm": true}', false, 30),
  -- ── الروابط (عامة: تظهر قبل الدخول) ──
  ('site_url', 'text', '"https://almohali.com"', null, null, 200, 'links',
   'موقع العائلة', 'يُفتح من «عن التطبيق» ورابط المشاركة.',
   '{"pattern": "^https://[^[:space:]]+$", "pattern_ar": "الرابط يجب أن يبدأ بـ https://"}', true, 10),
  ('privacy_url', 'text', '"https://almohali.com/privacy"', null, null, 200, 'links',
   'سياسة الخصوصية', 'رابط الخصوصية بالعربي.',
   '{"pattern": "^https://[^[:space:]]+$", "pattern_ar": "الرابط يجب أن يبدأ بـ https://"}', true, 20),
  ('privacy_url_en', 'text', '"https://almohali.com/privacy/en"', null, null, 200, 'links',
   'سياسة الخصوصية (إنجليزي)', 'يُفتح حين تكون لغة التطبيق الإنجليزية.',
   '{"pattern": "^https://[^[:space:]]+$", "pattern_ar": "الرابط يجب أن يبدأ بـ https://"}', true, 30),
  ('terms_url', 'text', '"https://almohali.com/terms"', null, null, 200, 'links',
   'شروط الاستخدام', 'رابط الشروط بالعربي.',
   '{"pattern": "^https://[^[:space:]]+$", "pattern_ar": "الرابط يجب أن يبدأ بـ https://"}', true, 40),
  ('terms_url_en', 'text', '"https://almohali.com/terms/en"', null, null, 200, 'links',
   'شروط الاستخدام (إنجليزي)', 'يُفتح حين تكون لغة التطبيق الإنجليزية.',
   '{"pattern": "^https://[^[:space:]]+$", "pattern_ar": "الرابط يجب أن يبدأ بـ https://"}', true, 50),
  ('support_email', 'text', '"info@almohali.com"', null, null, 100, 'links',
   'بريد التواصل', 'البريد الرسمي في «عن التطبيق» والخصوصية.',
   '{"pattern": "^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$", "pattern_ar": "البريد غير صحيح"}', true, 60),
  -- ── عام ──
  ('greeting_morning_start_hour', 'int', '4', 0, 11, null, 'general',
   'بداية «صباح الخير» (الساعة)', 'من هذه الساعة حتى بداية العصر تظهر «صباح الخير»، وقبلها «مساء الخير».', '{}', false, 10),
  ('greeting_afternoon_start_hour', 'int', '12', 12, 16, null, 'general',
   'بداية العصر (الساعة)', 'من هذه الساعة تظهر «مساء الخير» بلون العصر.', '{}', false, 20),
  ('greeting_evening_start_hour', 'int', '17', 17, 23, null, 'general',
   'بداية المساء (الساعة)', 'من هذه الساعة تظهر «مساء الخير» بلون المساء.', '{}', false, 30)
) as v(key, kind, def, min_value, max_value, max_length, category, label_ar, help_ar, rules, is_public, sort);
