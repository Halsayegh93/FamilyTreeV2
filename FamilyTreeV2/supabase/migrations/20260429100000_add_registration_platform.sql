-- إضافة عمود منصة التسجيل لجدول profiles لتتبع من أي منصة سجّل العضو (ios / ipados / android / web)
alter table public.profiles
add column if not exists registration_platform text;

-- إعادة تحميل schema cache لـ PostgREST حتى تظهر الأعمدة الجديدة فوراً
notify pgrst, 'reload schema';
