-- إضافة عمود تفعيل شارة الإشعارات
-- Add badge_enabled column to profiles table

alter table public.profiles
add column if not exists badge_enabled boolean default true;
