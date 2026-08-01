-- إضافة عمود إخفاء تاريخ الميلاد
-- Add is_birth_date_hidden column to profiles table

alter table public.profiles
add column if not exists is_birth_date_hidden boolean default false;
