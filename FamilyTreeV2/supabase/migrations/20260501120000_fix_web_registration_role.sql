-- إصلاح تسجيل الموقع: المستخدم الجديد من الويب يحصل على role='pending' و status='pending'
-- المشكلة: handle_new_user_by_phone يضع role='member' لأي مستخدم جديد بدون هاتف
-- الحل: إذا phone فارغ (تسجيل ويب عبر email) → role='pending', status='pending'

CREATE OR REPLACE FUNCTION public.handle_new_user_by_phone()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  if new.phone is not null and exists (
    select 1 from public.profiles where phone_number = new.phone
  ) then
    -- عضو موجود بنفس رقم الهاتف → ربط الحساب الجديد بسجله
    update public.profiles
    set id = new.id
    where phone_number = new.phone;

  elsif new.phone is not null then
    -- عضو جديد عبر الهاتف (iOS OTP)
    insert into public.profiles (id, phone_number, full_name, role, status)
    values (
      new.id,
      new.phone,
      new.raw_user_meta_data->>'full_name',
      'member',
      'pending'
    );

  else
    -- تسجيل جديد عبر الموقع (email/password) — ينتظر موافقة الإدارة
    insert into public.profiles (id, full_name, role, status)
    values (
      new.id,
      new.raw_user_meta_data->>'full_name',
      'pending',
      'pending'
    );

  end if;

  return new;
end;
$function$;
