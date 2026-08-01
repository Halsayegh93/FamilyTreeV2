-- إضافة عمود صورة الغلاف المنفصل عن الصورة الشخصية
alter table public.profiles add column if not exists cover_url text;
