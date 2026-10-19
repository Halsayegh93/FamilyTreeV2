-- تراجع: البحث بالرقم وتحرير الرقم كما كانا قبل ٢٠٢٦-١٠-٠٤ (نسخة حرفية من السيرفر الحي)،
-- وإرجاع تنفيذ find_profile_id_by_auth_phone، وإزالة search_path الثابت عن الدوال الأربع.

create or replace function public.find_profiles_by_phone(p_phone text)
 returns table(id uuid, role text, status text)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  with target as (
    select right(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'), 8) as last8
  )
  select p.id, p.role, p.status
  from public.profiles p, target t
  where length(t.last8) = 8
    and right(regexp_replace(coalesce(p.phone_number, ''), '\D', '', 'g'), 8) = t.last8
  limit 20;
$function$;

create or replace function public.release_orphan_auth_phone(p_phone text)
 returns text
 language plpgsql
 security definer
 set search_path to 'public', 'auth'
as $function$
declare
  v_caller uuid := auth.uid();
  v_profile uuid := public.current_profile_id();
  v_digits text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
  v_caller_name text;
  v_released int := 0;
  r record;
begin
  if v_caller is null or v_profile is null then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_profile and p.status = 'active') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if length(v_digits) < 8 or length(v_digits) > 15 then
    return 'invalid_phone';
  end if;

  -- أي حامل للرقم مرتبط بعضو حقيقي؟ → لا نلمس شيئاً
  if exists (
    select 1 from auth.users u
    where u.id <> v_caller
      and regexp_replace(coalesce(u.phone, ''), '\D', '', 'g') = v_digits
      and (exists (select 1 from public.profiles p where p.id = u.id)
           or coalesce(u.raw_app_meta_data->>'profile_id', '') <> '')
  ) then
    return 'linked';
  end if;

  select full_name into v_caller_name from public.profiles where id = v_profile;

  for r in
    select u.id from auth.users u
    where u.id <> v_caller
      and regexp_replace(coalesce(u.phone, ''), '\D', '', 'g') = v_digits
  loop
    update auth.users set phone = null, phone_confirmed_at = null, updated_at = now()
    where id = r.id;
    v_released := v_released + 1;

    -- سجل للتراجع: المالك والمدير يعرفون الحساب والرقم
    insert into public.notifications (target_member_id, title, body, kind, created_by)
    select a.id,
           'تحرير رقم لتغيير الرقم',
           format('حُرّر الرقم +%s من حساب دخول غير مرتبط بعضو (%s) بطلب تغيير رقم من %s.',
                  v_digits, r.id, coalesce(v_caller_name, 'عضو')),
           'admin_request',
           v_profile
    from public.profiles a
    where a.role in ('owner', 'admin') and a.status = 'active';
  end loop;

  return case when v_released > 0 then 'released' else 'free' end;
end;
$function$;

grant execute on function public.find_profile_id_by_auth_phone(text, uuid) to authenticated;

alter function public.family_archive_validate_category_key() reset search_path;
alter function public.trg_profiles_deceased_no_admin_role() reset search_path;
alter function public.trg_profiles_protect_delete() reset search_path;
alter function public.notification_category(text, uuid, uuid) reset search_path;
