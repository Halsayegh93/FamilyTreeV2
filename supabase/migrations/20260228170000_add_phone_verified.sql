-- إضافة عمود is_phone_verified لتوثيق رقم الهاتف
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS is_phone_verified boolean NOT NULL DEFAULT false;
