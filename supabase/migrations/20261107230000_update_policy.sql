-- «فرض التحديث» من جديد (مقترح samples/force-update بموافقة المالك ٢٠٢٦-١١-٠٧). قاعدة المالك: كل شي على السيرفر.
-- APPLIED 2026-11-07 بموافقة المالك.
-- التراجع: supabase/rollback/20261107230000_update_policy_rollback.sql
-- التجربة المحلية: cd supabase/tests/family_links && node update_policy.test.mjs
--
-- العضو: (أ) تحديث اختياري — مربّع «فيه تحديث جديد» مرة لكل نسخة، و«لاحقاً» يرجعه بعد update_snooze_days يوم؛
--        (ب) إجباري من تاريخ — نفس المربّع بعدّ تنازلي، و«لاحقاً» تختفي آخر ٢٤ ساعة؛
--        (ج) إجباري — بعد الموعد، أو «إجباري الحين»، أو البناء أقل من الحد الأدنى: شاشة «حدّث التطبيق» بنصوص الإدارة.
--        المالكان مستثنيان من القفل دائماً (يظهر لهما المربّع بـ«لاحقاً» فقط).
-- أين القيم:
--   • app_settings.ios_min_build / android_min_build / ios_update_url / android_update_url — كما هي (تقرؤها النسخ الحالية).
--   • app_config (تُقرأ عبر app_config() لكل مسجّل، وتتغيّر عبر set_update_policy أو set_app_config للمالك):
--     ios_latest_build · android_latest_build · ios_latest_version · android_latest_version ·
--     update_mode_ios · update_mode_android (optional | scheduled | forced) ·
--     update_deadline_ios · update_deadline_android (ISO UTC أو فارغ) · update_snooze_days ·
--     update_whats_new (سطر لكل نقطة) · update_force_title · update_force_message ·
--     update_reminder_title · update_reminder_body (نص «ذكّرهم بإشعار»).
--   • app_settings.force_update + latest_build (نسخ الأندرويد القديمة) لا تُلمس هنا — مفتاحها «إيقاف نسخ الأندرويد القديمة».
-- device_tokens: app_build · app_version · build_seen_at — يكتبها التطبيق بعد تسجيل الجهاز عبر report_app_build
--   (الأعمدة لا تدخل upsert التسجيل، فالنسخ قبل الترحيل وبعده تسجّل أجهزتها كما هي).
-- الدوال:
--   app_update_policy(p_platform, p_build)  — لكل مسجّل: الحالة محسوبة على السيرفر (بوقته) + النصوص.
--   update_policy_admin()                   — للمالك: كل الإعدادات للمنصتين.
--   set_update_policy(p jsonb)              — للمالك: حفظ جزئي بفحص العلاقات (الأدنى ≤ الأخيرة، الموعد مع «من تاريخ»).
--   report_app_build(p_device_id, p_build, p_version) — المسجّل لجهازه هو.
--   app_build_overview(p_days)              — للمالك: «النسخ عند الأعضاء» (الحصص + قائمة الأقدم).

-- ═══ ١) أعمدة النسخة على الأجهزة ═══
alter table public.device_tokens
  add column if not exists app_build     integer,
  add column if not exists app_version   text,
  add column if not exists build_seen_at timestamptz;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'device_tokens_app_build_check') then
    alter table public.device_tokens
      add constraint device_tokens_app_build_check check (app_build is null or app_build between 0 and 100000000);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'device_tokens_app_version_check') then
    alter table public.device_tokens
      add constraint device_tokens_app_version_check check (app_version is null or char_length(app_version) <= 32);
  end if;
end $$;

-- ═══ ٢) المفاتيح ═══
insert into public.app_config (key, value, default_value, kind, min_value, max_value, max_length, category, label_ar, help_ar, rules, is_public, sort)
values
  ('ios_latest_build', '0', '0', 'int', 0, 100000000, null, 'general', 'آخر نسخة آيفون في المتجر (رقم البناء)',
   'رقم البناء (CFBundleVersion) لآخر نسخة في App Store. 0 = لا مربّع تحديث.', '{}', false, 200),
  ('android_latest_build', '0', '0', 'int', 0, 100000000, null, 'general', 'آخر نسخة أندرويد في المتجر (رقم البناء)',
   'رقم البناء (versionCode) لآخر نسخة في Google Play. 0 = لا مربّع تحديث.', '{}', false, 201),
  ('ios_latest_version', '""', '""', 'text', null, null, 20, 'general', 'اسم آخر نسخة آيفون (مثل 1.0.1)',
   'يظهر في مربّع التحديث بجانب رقم البناء. فارغ = الرقم فقط.',
   '{"min_length": 0, "pattern": "^([0-9]+(\\.[0-9]+){0,3})?$", "pattern_ar": "اسم النسخة أرقام ونقاط فقط (مثل 1.0.1)"}', false, 202),
  ('android_latest_version', '""', '""', 'text', null, null, 20, 'general', 'اسم آخر نسخة أندرويد (مثل 1.0.1)',
   'يظهر في مربّع التحديث بجانب رقم البناء. فارغ = الرقم فقط.',
   '{"min_length": 0, "pattern": "^([0-9]+(\\.[0-9]+){0,3})?$", "pattern_ar": "اسم النسخة أرقام ونقاط فقط (مثل 1.0.1)"}', false, 203),
  ('update_mode_ios', '"optional"', '"optional"', 'text', null, null, 16, 'general', 'نوع التحديث للآيفون',
   'للنسخ الأقدم من آخر نسخة: optional اختياري · scheduled إجباري من تاريخ · forced إجباري الحين.',
   '{"pattern": "^(optional|scheduled|forced)$", "pattern_ar": "النوع: optional أو scheduled أو forced"}', false, 204),
  ('update_mode_android', '"optional"', '"optional"', 'text', null, null, 16, 'general', 'نوع التحديث للأندرويد',
   'للنسخ الأقدم من آخر نسخة: optional اختياري · scheduled إجباري من تاريخ · forced إجباري الحين.',
   '{"pattern": "^(optional|scheduled|forced)$", "pattern_ar": "النوع: optional أو scheduled أو forced"}', false, 205),
  ('update_deadline_ios', '""', '""', 'text', null, null, 32, 'general', 'موعد الإجبار للآيفون',
   'بعده تنقفل النسخ الأقدم من آخر نسخة (مع «إجباري من تاريخ»). وقت عالمي ISO مثل 2026-11-20T21:00:00Z.',
   '{"min_length": 0, "pattern": "^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}(:[0-9]{2})?(Z|[+-][0-9]{2}:[0-9]{2}))?$", "pattern_ar": "الموعد بصيغة 2026-11-20T21:00:00Z"}', false, 206),
  ('update_deadline_android', '""', '""', 'text', null, null, 32, 'general', 'موعد الإجبار للأندرويد',
   'بعده تنقفل النسخ الأقدم من آخر نسخة (مع «إجباري من تاريخ»). وقت عالمي ISO مثل 2026-11-20T21:00:00Z.',
   '{"min_length": 0, "pattern": "^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}(:[0-9]{2})?(Z|[+-][0-9]{2}:[0-9]{2}))?$", "pattern_ar": "الموعد بصيغة 2026-11-20T21:00:00Z"}', false, 207),
  ('update_snooze_days', '2', '2', 'int', 1, 30, null, 'general', '«لاحقاً» يرجّع مربّع التحديث بعد (أيام)',
   'كم يوم بعد «لاحقاً» يرجع مربّع «فيه تحديث جديد».', '{}', false, 208),
  ('update_whats_new', '""', '""', 'text_long', null, null, 1200, 'general', 'ما الجديد في آخر نسخة',
   'سطر لكل نقطة. يظهر في مربّع التحديث وفي شاشة الإجبار.', '{"min_length": 0}', false, 209),
  ('update_force_title', '"حدّث التطبيق"', '"حدّث التطبيق"', 'text', null, null, 60, 'general', 'عنوان شاشة الإجبار',
   null, '{}', false, 210),
  ('update_force_message', '"نسختك قديمة. حدّث من المتجر عشان تكمل استخدام تطبيق عائلة المحمدعلي."',
   '"نسختك قديمة. حدّث من المتجر عشان تكمل استخدام تطبيق عائلة المحمدعلي."', 'text_long', null, null, 400, 'general',
   'رسالة شاشة الإجبار', null, '{}', false, 211),
  ('update_reminder_title', '"فيه تحديث جديد للتطبيق"', '"فيه تحديث جديد للتطبيق"', 'text', null, null, 80, 'general',
   'عنوان إشعار «ذكّرهم بإشعار»', null, '{}', false, 212),
  ('update_reminder_body', '"نسختك من تطبيق عائلة المحمدعلي قديمة. حدّث من المتجر عشان توصلك آخر الإضافات."',
   '"نسختك من تطبيق عائلة المحمدعلي قديمة. حدّث من المتجر عشان توصلك آخر الإضافات."', 'text_long', null, null, 300,
   'general', 'نص إشعار «ذكّرهم بإشعار»', null, '{}', false, 213)
on conflict (key) do nothing;

-- رسالة المالك السابقة (app_settings.update_message) تنتقل لشاشة الإجبار إن كانت مكتوبة (مرة — لا يمسّ تعديلاً لاحقاً)
update public.app_config c
   set value = to_jsonb(left(btrim(s.update_message), 400))
  from (select a.update_message from public.app_settings a order by a.updated_at desc nulls last limit 1) s
 where c.key = 'update_force_message' and c.value = c.default_value
   and coalesce(btrim(s.update_message), '') <> '';

-- ═══ ٣) قراءة القيم (داخلية) ═══
create or replace function private.update_policy_values(p_platform text)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_cfg jsonb;
  v_min integer;
  v_url text;
begin
  select coalesce(jsonb_object_agg(c.key, c.value), '{}'::jsonb) into v_cfg
    from public.app_config c
   where c.key in (p_platform || '_latest_build', p_platform || '_latest_version', 'update_mode_' || p_platform,
                   'update_deadline_' || p_platform);
  select case when p_platform = 'ios' then a.ios_min_build else a.android_min_build end,
         case when p_platform = 'ios' then a.ios_update_url else a.android_update_url end
    into v_min, v_url
    from public.app_settings a order by a.updated_at desc nulls last limit 1;
  return jsonb_build_object(
    'latest_build',   coalesce((v_cfg ->> (p_platform || '_latest_build'))::integer, 0),
    'latest_version', coalesce(v_cfg ->> (p_platform || '_latest_version'), ''),
    'min_build',      coalesce(v_min, 0),
    'mode',           coalesce(v_cfg ->> ('update_mode_' || p_platform), 'optional'),
    'deadline',       nullif(v_cfg ->> ('update_deadline_' || p_platform), ''),
    'update_url',     nullif(btrim(coalesce(v_url, '')), ''));
end;
$function$;

create or replace function private.update_policy_texts()
returns jsonb
language sql
stable
security definer
set search_path to ''
as $function$
  select jsonb_build_object(
    'snooze_days',    coalesce((select (c.value #>> '{}')::integer from public.app_config c where c.key = 'update_snooze_days'), 2),
    'whats_new',      coalesce((select c.value #>> '{}' from public.app_config c where c.key = 'update_whats_new'), ''),
    'force_title',    coalesce((select c.value #>> '{}' from public.app_config c where c.key = 'update_force_title'), ''),
    'force_message',  coalesce((select c.value #>> '{}' from public.app_config c where c.key = 'update_force_message'), ''),
    'reminder_title', coalesce((select c.value #>> '{}' from public.app_config c where c.key = 'update_reminder_title'), ''),
    'reminder_body',  coalesce((select c.value #>> '{}' from public.app_config c where c.key = 'update_reminder_body'), ''));
$function$;

revoke all on function private.update_policy_values(text) from public, anon, authenticated;
revoke all on function private.update_policy_texts() from public, anon, authenticated;

-- ═══ ٤) العضو: حالة نسخته ═══
create or replace function public.app_update_policy(p_platform text, p_build integer)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_role     text := coalesce(public.current_user_role(), '');
  v_platform text := case lower(coalesce(p_platform, '')) when 'ios' then 'ios' when 'ipados' then 'ios'
                                                         when 'android' then 'android' end;
  v          jsonb;
  t          jsonb;
  v_latest   integer;
  v_min      integer;
  v_mode     text;
  v_deadline timestamptz;
  v_state    text := 'none';
  v_reason   text;
  v_exempt   boolean := v_role = 'owner';
  v_snooze   boolean := true;
begin
  if public.current_profile_id() is null then
    raise exception 'سجّل الدخول أولاً' using errcode = '42501', hint = 'not_allowed';
  end if;
  if v_platform is null then
    raise exception 'المنصة ios أو android' using errcode = '22023', hint = 'bad_value';
  end if;
  v := private.update_policy_values(v_platform);
  t := private.update_policy_texts();
  v_latest := (v ->> 'latest_build')::integer;
  v_min    := (v ->> 'min_build')::integer;
  v_mode   := v ->> 'mode';
  begin
    v_deadline := (v ->> 'deadline')::timestamptz;
  exception when others then
    v_deadline := null;
  end;

  if p_build is not null and v_min > 0 and p_build < v_min then
    v_state := 'forced'; v_reason := 'min_build';
  elsif p_build is not null and v_latest > 0 and p_build < v_latest then
    if v_mode = 'forced' then
      v_state := 'forced'; v_reason := 'forced_now';
    elsif v_mode = 'scheduled' and v_deadline is not null then
      if now() >= v_deadline then
        v_state := 'forced'; v_reason := 'deadline';
      else
        v_state := 'scheduled';
        v_snooze := v_deadline - now() > interval '1 day';
      end if;
    else
      v_state := 'optional';
    end if;
  end if;

  -- المالكان لا ينقفلان أبداً — يشوفان المربّع بـ«لاحقاً»
  if v_exempt and v_state in ('forced', 'scheduled') then
    v_state := 'optional';
    v_snooze := true;
  end if;

  return jsonb_build_object(
    'platform', v_platform,
    'build', p_build,
    'state', v_state,
    'reason', v_reason,
    'exempt', v_exempt,
    'can_snooze', v_snooze,
    'latest_build', v_latest,
    'latest_version', v ->> 'latest_version',
    'min_build', v_min,
    'mode', v_mode,
    'deadline', v_deadline,
    'update_url', v -> 'update_url',
    'snooze_days', t -> 'snooze_days',
    'whats_new', coalesce((select jsonb_agg(btrim(l) order by n)
                             from unnest(string_to_array(t ->> 'whats_new', E'\n')) with ordinality as x(l, n)
                            where btrim(l) <> ''), '[]'::jsonb),
    'force_title', t -> 'force_title',
    'force_message', t -> 'force_message',
    'server_now', now());
end;
$function$;

-- ═══ ٥) المالك: القراءة والحفظ ═══
create or replace function public.update_policy_admin()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
begin
  if coalesce(public.current_user_role(), '') <> 'owner' then
    raise exception '«فرض التحديث» للمالك فقط' using errcode = '42501', hint = 'not_allowed';
  end if;
  return private.update_policy_texts() || jsonb_build_object(
    'ios', private.update_policy_values('ios'),
    'android', private.update_policy_values('android'),
    'legacy_android', (select jsonb_build_object('force_update', coalesce(a.force_update, false),
                                                 'latest_build', coalesce(a.latest_build, 0))
                         from public.app_settings a order by a.updated_at desc nulls last limit 1),
    'server_now', now());
end;
$function$;

create or replace function public.set_update_policy(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_me       uuid := public.current_profile_id();
  v_key      text;
  v_platform text;
  v_in       jsonb;
  v_cur      jsonb;
  v_latest   integer;
  v_min      integer;
  v_mode     text;
  v_deadline text;
  v_ts       timestamptz;
  v_url      text;
  v_settings uuid;
  v_text     text;
begin
  if coalesce(public.current_user_role(), '') <> 'owner' then
    raise exception '«فرض التحديث» للمالك فقط' using errcode = '42501', hint = 'not_allowed';
  end if;
  if p is null or jsonb_typeof(p) <> 'object' then
    raise exception 'القيم يجب أن تكون كائناً' using errcode = '22023', hint = 'bad_value';
  end if;
  for v_key in select jsonb_object_keys(p) loop
    if v_key not in ('ios', 'android', 'snooze_days', 'whats_new', 'force_title', 'force_message',
                     'reminder_title', 'reminder_body') then
      raise exception 'مفتاح غير معروف: %', v_key using errcode = '22023', hint = 'bad_value';
    end if;
  end loop;
  select a.id into v_settings from public.app_settings a order by a.updated_at desc nulls last limit 1;

  foreach v_platform in array array['ios', 'android'] loop
    continue when not p ? v_platform;
    v_in := p -> v_platform;
    if jsonb_typeof(v_in) <> 'object' then
      raise exception 'قيم % يجب أن تكون كائناً', v_platform using errcode = '22023', hint = 'bad_value';
    end if;
    for v_key in select jsonb_object_keys(v_in) loop
      if v_key not in ('latest_build', 'latest_version', 'min_build', 'mode', 'deadline', 'update_url') then
        raise exception 'مفتاح غير معروف في %: %', v_platform, v_key using errcode = '22023', hint = 'bad_value';
      end if;
    end loop;
    v_cur := private.update_policy_values(v_platform);
    -- القيم الجديدة فوق الحالية (ما لم يُرسل يبقى)
    begin
      v_latest := coalesce((v_in ->> 'latest_build')::integer, (v_cur ->> 'latest_build')::integer);
      v_min    := coalesce((v_in ->> 'min_build')::integer, (v_cur ->> 'min_build')::integer);
    exception when others then
      raise exception 'رقم البناء يجب أن يكون رقماً صحيحاً' using errcode = '22023', hint = 'bad_value';
    end;
    v_mode     := coalesce(v_in ->> 'mode', v_cur ->> 'mode');
    v_deadline := case when v_in ? 'deadline' then nullif(btrim(coalesce(v_in ->> 'deadline', '')), '')
                       else v_cur ->> 'deadline' end;
    if v_latest < 0 or v_min < 0 then
      raise exception 'رقم البناء لا يكون سالباً' using errcode = '22023', hint = 'bad_value';
    end if;
    if v_latest > 0 and v_min > v_latest then
      raise exception 'أقل نسخة مسموحة (%) أكبر من آخر نسخة في المتجر (%)', v_min, v_latest
        using errcode = '22023', hint = 'min_above_latest';
    end if;
    if v_mode not in ('optional', 'scheduled', 'forced') then
      raise exception 'نوع التحديث: اختياري أو إجباري من تاريخ أو إجباري الحين' using errcode = '22023', hint = 'bad_value';
    end if;
    if v_deadline is not null then
      begin
        v_ts := v_deadline::timestamptz;
      exception when others then
        raise exception 'الموعد غير صالح' using errcode = '22023', hint = 'bad_deadline';
      end;
      v_deadline := to_char(v_ts at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
    end if;
    if v_mode = 'scheduled' and v_deadline is null then
      raise exception '«إجباري من تاريخ» يحتاج موعداً' using errcode = '22023', hint = 'deadline_required';
    end if;

    update public.app_config set value = to_jsonb(v_latest), updated_at = now(), updated_by = v_me
     where key = v_platform || '_latest_build' and value is distinct from to_jsonb(v_latest);
    if v_in ? 'latest_version' then
      update public.app_config set value = to_jsonb(btrim(coalesce(v_in ->> 'latest_version', ''))), updated_at = now(),
             updated_by = v_me
       where key = v_platform || '_latest_version'
         and value is distinct from to_jsonb(btrim(coalesce(v_in ->> 'latest_version', '')));
    end if;
    update public.app_config set value = to_jsonb(v_mode), updated_at = now(), updated_by = v_me
     where key = 'update_mode_' || v_platform and value is distinct from to_jsonb(v_mode);
    update public.app_config set value = to_jsonb(coalesce(v_deadline, '')), updated_at = now(), updated_by = v_me
     where key = 'update_deadline_' || v_platform and value is distinct from to_jsonb(coalesce(v_deadline, ''));

    v_url := case when v_in ? 'update_url' then nullif(btrim(coalesce(v_in ->> 'update_url', '')), '')
                  else v_cur ->> 'update_url' end;
    if v_url is not null and v_url !~ '^https://[^[:space:]]+$' then
      raise exception 'رابط المتجر يبدأ بـ https://' using errcode = '22023', hint = 'bad_url';
    end if;
    if v_platform = 'ios' then
      update public.app_settings
         set ios_min_build = v_min, ios_update_url = v_url, updated_at = now(), updated_by = v_me
       where id = v_settings and (ios_min_build is distinct from v_min or ios_update_url is distinct from v_url);
    else
      update public.app_settings
         set android_min_build = v_min, android_update_url = v_url, updated_at = now(), updated_by = v_me
       where id = v_settings and (android_min_build is distinct from v_min or android_update_url is distinct from v_url);
    end if;
  end loop;

  -- النصوص المشتركة — فحص كل مفتاح بقواعده (trg_app_config_guard)
  for v_key, v_text in select k, m from (values ('snooze_days', 'update_snooze_days'), ('whats_new', 'update_whats_new'),
                                               ('force_title', 'update_force_title'), ('force_message', 'update_force_message'),
                                               ('reminder_title', 'update_reminder_title'),
                                               ('reminder_body', 'update_reminder_body')) as x(k, m) loop
    continue when not p ? v_key;
    if v_key = 'whats_new' then
      -- أسطر نظيفة: بلا فراغ زائد ولا أسطر فارغة
      update public.app_config
         set value = to_jsonb(coalesce((select string_agg(btrim(l), E'\n' order by n)
                                          from unnest(string_to_array(replace(coalesce(p ->> v_key, ''), E'\r', ''), E'\n'))
                                               with ordinality as y(l, n)
                                         where btrim(l) <> ''), '')),
             updated_at = now(), updated_by = v_me
       where key = v_text;
    elsif v_key = 'snooze_days' then
      update public.app_config set value = p -> v_key, updated_at = now(), updated_by = v_me
       where key = v_text and value is distinct from p -> v_key;
    else
      update public.app_config
         set value = case when nullif(btrim(coalesce(p ->> v_key, '')), '') is null then default_value
                          else to_jsonb(btrim(p ->> v_key)) end,
             updated_at = now(), updated_by = v_me
       where key = v_text;
    end if;
  end loop;

  return public.update_policy_admin();
end;
$function$;

-- ═══ ٦) الجهاز يبلّغ نسخته ═══
create or replace function public.report_app_build(p_device_id text, p_build integer, p_version text default null)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_me uuid := public.current_profile_id();
  v_n  integer;
begin
  if v_me is null or coalesce(btrim(p_device_id), '') = '' then
    return false;
  end if;
  if p_build is null or p_build < 0 or p_build > 100000000 then
    raise exception 'رقم البناء غير صالح' using errcode = '22023', hint = 'bad_value';
  end if;
  update public.device_tokens d
     set app_build = p_build,
         app_version = left(nullif(btrim(coalesce(p_version, '')), ''), 32),
         build_seen_at = now()
   where d.device_id = p_device_id
     and d.member_id in (v_me, auth.uid());
  get diagnostics v_n = row_count;
  return v_n > 0;
end;
$function$;

-- ═══ ٧) المالك: «النسخ عند الأعضاء» ═══
create or replace function public.app_build_overview(p_days integer default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_days   integer := greatest(1, least(coalesce(p_days, 30), 365));
  v_since  timestamptz := now() - make_interval(days => greatest(1, least(coalesce(p_days, 30), 365)));
  v_out    jsonb := '{}'::jsonb;
  v_plat   text;
  v_latest integer;
  v_stats  jsonb;
begin
  if coalesce(public.current_user_role(), '') <> 'owner' then
    raise exception '«النسخ عند الأعضاء» للمالك فقط' using errcode = '42501', hint = 'not_allowed';
  end if;

  foreach v_plat in array array['ios', 'android'] loop
    -- آخر نسخة: من الإعداد، وإن لم يُضبط فأعلى نسخة بلّغ عنها جهاز
    select coalesce(nullif((select (c.value #>> '{}')::integer from public.app_config c
                             where c.key = v_plat || '_latest_build'), 0),
                    (select max(d.app_build) from public.device_tokens d
                      where (case when d.platform in ('ios', 'ipados') then 'ios' else d.platform end) = v_plat
                        and greatest(d.build_seen_at, d.updated_at) >= v_since), 0)
      into v_latest;
    with dev as (
      select d.app_build
        from public.device_tokens d
       where (case when d.platform in ('ios', 'ipados') then 'ios' else d.platform end) = v_plat
         and greatest(d.build_seen_at, d.updated_at) >= v_since)
    select jsonb_build_object(
             'latest_build', v_latest,
             'total', count(*),
             'on_latest', count(*) filter (where app_build is not null and app_build >= v_latest),
             'older', count(*) filter (where app_build is not null and app_build < v_latest),
             'unknown', count(*) filter (where app_build is null),
             'builds', coalesce((select jsonb_agg(jsonb_build_object('build', b.app_build, 'count', b.n) order by b.app_build desc)
                                   from (select app_build, count(*) n from dev where app_build is not null group by app_build) b),
                                '[]'::jsonb))
      into v_stats
      from dev;
    v_out := v_out || jsonb_build_object(v_plat, v_stats);
  end loop;

  -- الأجهزة على نسخة قديمة (أو لم تبلّغ — نسخ قبل هذه الميزة)، الأحدث ظهوراً أولاً
  return v_out || jsonb_build_object(
    'days', v_days,
    'server_now', now(),
    'devices', coalesce((
      select jsonb_agg(x order by x.last_seen desc)
        from (select d.member_id,
                     coalesce(nullif(btrim(p.full_name), ''), nullif(btrim(p.first_name), ''), '—') as name,
                     case when d.platform in ('ios', 'ipados') then 'ios' else d.platform end as platform,
                     d.app_build as build,
                     d.app_version as version,
                     d.device_name,
                     greatest(d.build_seen_at, d.updated_at) as last_seen
                from public.device_tokens d
                join public.profiles p on p.id = d.member_id
               where greatest(d.build_seen_at, d.updated_at) >= v_since
                 and (d.app_build is null
                      or d.app_build < coalesce(nullif((select (c.value #>> '{}')::integer from public.app_config c
                                                         where c.key = (case when d.platform in ('ios', 'ipados') then 'ios'
                                                                             else d.platform end) || '_latest_build'), 0),
                                                (select max(d2.app_build) from public.device_tokens d2
                                                  where (case when d2.platform in ('ios', 'ipados') then 'ios' else d2.platform end)
                                                        = (case when d.platform in ('ios', 'ipados') then 'ios' else d.platform end)
                                                    and greatest(d2.build_seen_at, d2.updated_at) >= v_since), 0))
               order by greatest(d.build_seen_at, d.updated_at) desc
               limit 500) x), '[]'::jsonb));
end;
$function$;

revoke all on function public.app_update_policy(text, integer) from public, anon;
revoke all on function public.update_policy_admin() from public, anon;
revoke all on function public.set_update_policy(jsonb) from public, anon;
revoke all on function public.report_app_build(text, integer, text) from public, anon;
revoke all on function public.app_build_overview(integer) from public, anon;
grant execute on function public.app_update_policy(text, integer) to authenticated;
grant execute on function public.update_policy_admin() to authenticated;
grant execute on function public.set_update_policy(jsonb) to authenticated;
grant execute on function public.report_app_build(text, integer, text) to authenticated;
grant execute on function public.app_build_overview(integer) to authenticated;

notify pgrst, 'reload schema';
