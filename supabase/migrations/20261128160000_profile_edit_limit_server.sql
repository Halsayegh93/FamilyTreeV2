-- «حدّ التعديلات الذاتية» على السيرفر للتطبيقات (قرار المالك ٢٠٢٦-١١-٢٨ «صلّح الأخطاء كلها»)
--
-- الخلل: مفتاح «حدّ التعديلات الذاتية» و«إعادة ضبط العدّاد» في «الإدارة ← التطبيق ← التعديلات الذاتية» كانا يُحفظان على
-- جهاز المالك فقط (الآيفون ProfileEditCooldown في UserDefaults/Keychain، والأندرويد profile_edit_limit.dart في
-- SharedPreferences)، والعدّاد نفسه لكل جهاز — فلا مفتاح المالك يصل الأعضاء، ولا إعادة الضبط تصفّر عدّاد أحد غيره.
--
-- الموجود على السيرفر من قبل (حيّ منذ ٢٠٢٦-١٠-٢٢ بلا ملف ترحيل في المستودع، ولا يستعمله تطبيق) ويُثبَّت هنا كما هو:
--   app_config.profile_edit_limit_enabled (bool) · app_config.profile_free_edits (int، ٣)
--   public.profile_edit_counts (member_id, field, edits, last_edit_at) — عدّاد لكل عضو ولكل حقل
--   trg_profiles_self_edit_limit (BEFORE UPDATE على profiles) ← profile_edit_limit_consume: العضو والمشرف فقط، تعديله على
--     ملفه هو مباشرة من التطبيق (current_user = authenticated)، بعد الحدّ يرفض (P0001، hint = edit_limit_reached،
--     detail = الحقول)؛ المالك والمدير والمراقب معفون.
--   profile_edit_limits(p_member_id) — الحالة والعدّاد (العضو لنفسه، المالك والمدير لأي عضو).
--   reset_profile_edit_counts(p_member_id, p_field) — تصفير: الكل للمالك، وعضو واحد للمالك والمدير.
--
-- الجديد: الحقل isPhoneHidden («إظهار الرقم») — الآيفون والأندرويد يحسبانه ضمن الحدّ، والسيرفر لم يكن يحسبه.
-- (تراجعنا عنه في اليوم نفسه: 20261128161000 — «إظهار الرقم» خيار خصوصية يُغيَّر بلا حدّ من شاشات أخرى.)
-- التطبيقات بعد هذا: المفتاح = set_app_config('profile_edit_limit_enabled', true|false)، إعادة الضبط =
-- reset_profile_edit_counts() (كل الأعضاء)، والعضو يقرأ profile_edit_limits() قبل الحفظ.
--
-- مطبَّق على الحي ٢٠٢٦-١١-٢٨ بعد تجربة begin…rollback (عضو: ٣ تعديلات مباشرة لإظهار الرقم ثم الرابع edit_limit_reached،
-- profile_edit_limits يعرض isPhoneHidden، reset_profile_edit_counts() من المالك يصفّر، والمدير بلا عضو مرفوض).
-- القيمة الحالية لـ profile_edit_limit_enabled لم تُغيَّر (مطفأة منذ ٢٠٢٦-١٠-٢٢) — تشغيلها قرار المالك من المفتاح.

alter table public.profile_edit_counts drop constraint if exists profile_edit_counts_field_check;
alter table public.profile_edit_counts
  add constraint profile_edit_counts_field_check
  check (field = any (array['birthDate', 'isMarried', 'bio', 'avatar', 'phoneNumber', 'isPhoneHidden']));

create or replace function public.trg_profiles_self_edit_limit()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
declare
  v_fields text[] := '{}';
begin
  if current_user <> 'authenticated' then
    return new;
  end if;
  if new.birth_date is distinct from old.birth_date then
    v_fields := array_append(v_fields, 'birthDate');
  end if;
  if coalesce(new.is_married, false) is distinct from coalesce(old.is_married, false) then
    v_fields := array_append(v_fields, 'isMarried');
  end if;
  if new.bio_json is distinct from old.bio_json then
    v_fields := array_append(v_fields, 'bio');
  end if;
  if new.avatar_url is not null and new.avatar_url is distinct from old.avatar_url then
    v_fields := array_append(v_fields, 'avatar');
  end if;
  if new.phone_number is distinct from old.phone_number then
    v_fields := array_append(v_fields, 'phoneNumber');
  end if;
  if coalesce(new.is_phone_hidden, false) is distinct from coalesce(old.is_phone_hidden, false) then
    v_fields := array_append(v_fields, 'isPhoneHidden');
  end if;
  if cardinality(v_fields) > 0 then
    perform public.profile_edit_limit_consume(new.id, v_fields);
  end if;
  return new;
end;
$function$;

-- المشغّل كان «UPDATE OF» خمسة أعمدة — يُضاف is_phone_hidden
drop trigger if exists trg_profiles_self_edit_limit on public.profiles;
create trigger trg_profiles_self_edit_limit
  before update of birth_date, is_married, bio_json, avatar_url, phone_number, is_phone_hidden on public.profiles
  for each row execute function public.trg_profiles_self_edit_limit();

create or replace function public.profile_edit_limits(p_member_id uuid default null::uuid)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare
  v_me     uuid := public.current_profile_id();
  v_role   text := coalesce(public.current_user_role(), '');
  v_target uuid := coalesce(p_member_id, public.current_profile_id());
  v_t_role text;
  v_free   integer := greatest(public.config_int('profile_free_edits', 3), 0);
  v_on     boolean := public.config_bool('profile_edit_limit_enabled', true);
begin
  if v_target is null then
    raise exception 'غير مسجّل' using errcode = '42501', hint = 'not_allowed';
  end if;
  if v_target is distinct from v_me and v_role not in ('owner', 'admin') then
    raise exception 'عدّادات غيرك للمالك والمدير فقط' using errcode = '42501', hint = 'not_allowed';
  end if;
  select case when p.status = 'active' then p.role when p.status in ('frozen', 'deleted') then p.status else 'pending' end
    into v_t_role from public.profiles p where p.id = v_target;
  return jsonb_build_object(
    'member_id', v_target,
    'enabled', v_on,
    'free_edits', v_free,
    'exempt', coalesce(v_t_role, '') not in ('member', 'supervisor'),
    'fields', (select jsonb_object_agg(f.field, jsonb_build_object(
                        'used', coalesce(c.edits, 0),
                        'remaining', greatest(v_free - coalesce(c.edits, 0), 0),
                        'last_edit_at', c.last_edit_at))
                 from unnest(array['birthDate', 'isMarried', 'bio', 'avatar', 'phoneNumber', 'isPhoneHidden']) as f(field)
                 left join public.profile_edit_counts c on c.member_id = v_target and c.field = f.field));
end;
$function$;

create or replace function public.reset_profile_edit_counts(p_member_id uuid default null::uuid, p_field text default null::text)
 returns integer
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_role text := coalesce(public.current_user_role(), '');
  v_n    integer;
begin
  if v_role not in ('owner', 'admin') or (p_member_id is null and v_role <> 'owner') then
    raise exception 'تصفير العدّاد للمالك (والمدير لعضو واحد)' using errcode = '42501', hint = 'not_allowed';
  end if;
  if p_field is not null and p_field not in ('birthDate', 'isMarried', 'bio', 'avatar', 'phoneNumber', 'isPhoneHidden') then
    raise exception 'حقل غير معروف: %', p_field using errcode = '22023', hint = 'bad_value';
  end if;
  delete from public.profile_edit_counts c
   where (p_member_id is null or c.member_id = p_member_id)
     and (p_field is null or c.field = p_field);
  get diagnostics v_n = row_count;
  return v_n;
end;
$function$;

revoke all on function public.profile_edit_limits(uuid) from public, anon;
revoke all on function public.reset_profile_edit_counts(uuid, text) from public, anon;
grant execute on function public.profile_edit_limits(uuid) to authenticated;
grant execute on function public.reset_profile_edit_counts(uuid, text) to authenticated;
