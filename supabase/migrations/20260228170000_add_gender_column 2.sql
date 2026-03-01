-- إضافة عمود الجنس لجدول profiles
alter table public.profiles
add column if not exists gender text;
