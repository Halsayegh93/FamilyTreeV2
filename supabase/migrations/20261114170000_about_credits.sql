-- «أسماء عن التطبيق» (طلب المالك ٢٠٢٦-١١-١٤: النموذج «ج» + «أضيف أكثر من اسم» + «صفحة في الإدارة»)
--
-- مفتاح جديد في app_config: about_credits = قائمة [{"role": "فكرة وتنفيذ", "name": "حسن الصايغ",
-- "role_en": "…", "name_en": "…"}] بالترتيب. يقرؤها كل مسجّل عبر app_config() (مربّع «عن التطبيق»)، ويعدّلها المالك
-- وحده عبر set_app_config الموجودة (صفحة «الإدارة ← التطبيق ← أسماء عن التطبيق»).
--
-- الفحص حارس مستقل لهذا المفتاح وحده (مثل trg_app_config_role_matrix_guard) — private.app_config_problem الحيّة لا تتغيّر:
--   • قائمة من ١ إلى ٢٠ عنصراً، كل عنصر كائن بالمفاتيح role / name / role_en / name_en فقط
--   • name نص مطلوب (١–٦٠ حرفاً بعد القصّ)، role اختياري (حتى ٤٠)، role_en/name_en اختياريان (حتى ٤٠/٦٠)، بلا أسطر جديدة
--
-- القيمة الأولى = ما يعرضه التطبيق اليوم: «فكرة وتنفيذ: حسن الصايغ».
-- التجربة: cd supabase/tests/family_links && node about_credits.test.mjs — التراجع: rollback/20261114170000_about_credits_rollback.sql

create or replace function private.about_credits_problem(p jsonb)
returns text
language plpgsql
immutable
set search_path to ''
as $function$
declare
  v_item jsonb;
  v_key  text;
  v_n    integer;
  v_len  integer;
  v_max  integer;
  v_text text;
begin
  if p is null or jsonb_typeof(p) <> 'array' then
    return 'القيمة يجب أن تكون قائمة أسماء';
  end if;
  v_n := jsonb_array_length(p);
  if v_n < 1 or v_n > 20 then
    return 'عدد الأسماء يجب أن يكون بين 1 و20';
  end if;
  for v_item in select e from jsonb_array_elements(p) e loop
    if jsonb_typeof(v_item) <> 'object' then
      return 'كل سطر يجب أن يكون {"role": …, "name": …}';
    end if;
    for v_key in select jsonb_object_keys(v_item) loop
      if v_key not in ('role', 'name', 'role_en', 'name_en') then
        return 'مفتاح غير معروف: ' || v_key;
      end if;
      if jsonb_typeof(v_item -> v_key) <> 'string' then
        return 'قيمة «' || v_key || '» يجب أن تكون نصاً';
      end if;
      v_text := v_item ->> v_key;
      if v_text ~ '[\r\n]' then
        return 'بلا أسطر جديدة في «' || v_key || '»';
      end if;
      v_len := char_length(btrim(v_text));
      v_max := case when v_key like 'name%' then 60 else 40 end;
      if v_len > v_max then
        return 'النص في «' || v_key || '» أطول من المسموح';
      end if;
    end loop;
    if char_length(btrim(coalesce(v_item ->> 'name', ''))) = 0 then
      return 'الاسم مطلوب في كل سطر';
    end if;
  end loop;
  return null;
end;
$function$;

create or replace function private.app_config_about_credits_guard()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare v_msg text;
begin
  v_msg := private.about_credits_problem(new.default_value);
  if v_msg is not null then
    raise exception 'الافتراضي لـ %: %', new.key, v_msg using errcode = '22023', hint = 'bad_value';
  end if;
  v_msg := private.about_credits_problem(new.value);
  if v_msg is not null then
    raise exception '%', v_msg using errcode = '22023', hint = 'bad_value';
  end if;
  return new;
end;
$function$;

revoke all on function private.about_credits_problem(jsonb) from public, anon, authenticated;
revoke all on function private.app_config_about_credits_guard() from public, anon, authenticated;

drop trigger if exists trg_app_config_about_credits_guard on public.app_config;
create trigger trg_app_config_about_credits_guard
  before insert or update on public.app_config
  for each row when (new.key = 'about_credits')
  execute function private.app_config_about_credits_guard();

insert into public.app_config (key, value, default_value, kind, category, label_ar, help_ar, rules, is_public, sort)
values ('about_credits',
        '[{"role": "فكرة وتنفيذ", "name": "حسن الصايغ", "role_en": "Idea and development", "name_en": "Hasan Al-Sayegh"}]'::jsonb,
        '[{"role": "فكرة وتنفيذ", "name": "حسن الصايغ", "role_en": "Idea and development", "name_en": "Hasan Al-Sayegh"}]'::jsonb,
        'json', 'general',
        'أسماء «عن التطبيق»',
        'الأسماء في مربّع «عن التطبيق» بالترتيب: الصفة (اختيارية) فوق الاسم. من 1 إلى 20 اسماً.',
        '{}'::jsonb, false, 96)
on conflict (key) do nothing;
