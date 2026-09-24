-- تحرير رقم من حساب دخول «يتيم» عند طلب تغيير الرقم — 2026-09-23 (طلب المالك)
--
-- المشكلة: Supabase Auth يرفض إرسال رمز تغيير الرقم إذا الرقم مسجّل على حساب
-- دخول آخر («A user with this phone number has already been registered») —
-- حتى لو كان حساباً يتيماً بلا عضو (دخل مرة ولم يكمل التسجيل). مثال:
-- +96594942623 على حساب دخول أُنشئ 2026-04-06 بلا ملف في profiles.
--
-- الحل (قابل للتراجع، بلا حذف): العضو المفعّل يطلب تحرير الرقم؛ إن كانت كل
-- الحسابات الحاملة للرقم يتيمة (لا ملف لها ولا ربط) يُفرَّغ رقمها فقط، ويُبلَّغ
-- المالك/المدير بمعرّف الحساب والرقم (للتراجع عند الحاجة). حساب مرتبط بعضو
-- حقيقي لا يُلمس — تُرجع 'linked' ويذهب الطلب للإدارة.
-- لا يتغيّر رقم أحد هنا: بعدها يطلب التطبيق رمز تغيير الرقم من Supabase Auth،
-- ولا ينتقل الرقم إلا بعد إدخال الرمز الصحيح.

begin;

create or replace function public.release_orphan_auth_phone(p_phone text)
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
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
$$;

revoke all on function public.release_orphan_auth_phone(text) from public, anon;
grant execute on function public.release_orphan_auth_phone(text) to authenticated;

commit;
