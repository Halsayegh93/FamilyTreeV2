-- «حدّ التعديلات الذاتية»: «إظهار الرقم» خارج الحدّ (٢٠٢٦-١١-٢٨، بعد 20261128160000 في اليوم نفسه)
--
-- 20261128160000 أضاف isPhoneHidden للحقول التي يعدّها السيرفر. لكن «إظهار الرقم» خيار خصوصية يُغيَّر أيضاً من مربّع
-- «البيانات الشخصية» ونداءات الخصوصية (`updatePhoneHidden` في الآيفون) بلا حدّ — عدّه على السيرفر يرفض مفتاح الخصوصية بعد
-- ٣ مرات حين يُشغَّل الحدّ. فيعود السيرفر إلى الحقول الخمسة الأصلية (الميلاد، الحالة الاجتماعية، السيرة، الصورة، الرقم)،
-- والتطبيقات لا تحسب «إظهار الرقم» ضمن الحدّ. لم يُسجَّل أي صفّ isPhoneHidden (الحدّ مطفأ) — القيد يعود بلا تنظيف.
--
-- مطبَّق على الحي ٢٠٢٦-١١-٢٨ بعد تجربة begin…rollback (عضو: تغيير إظهار الرقم ٤ مرات بلا رفض والحدّ مفعّل داخل
-- التجربة، والسيرة تُرفض في الرابعة؛ profile_edit_limits بخمسة حقول).

alter table public.profile_edit_counts drop constraint if exists profile_edit_counts_field_check;
alter table public.profile_edit_counts
  add constraint profile_edit_counts_field_check
  check (field = any (array['birthDate', 'isMarried', 'bio', 'avatar', 'phoneNumber']));

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
  if cardinality(v_fields) > 0 then
    perform public.profile_edit_limit_consume(new.id, v_fields);
  end if;
  return new;
end;
$function$;

-- المشغّل يعود «UPDATE OF» الأعمدة الخمسة
drop trigger if exists trg_profiles_self_edit_limit on public.profiles;
create trigger trg_profiles_self_edit_limit
  before update of birth_date, is_married, bio_json, avatar_url, phone_number on public.profiles
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
                 from unnest(array['birthDate', 'isMarried', 'bio', 'avatar', 'phoneNumber']) as f(field)
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
  if p_field is not null and p_field not in ('birthDate', 'isMarried', 'bio', 'avatar', 'phoneNumber') then
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
