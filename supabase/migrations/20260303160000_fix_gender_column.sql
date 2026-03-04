-- إعادة إضافة عمود الجنس (قد يكون مفقود بسبب repair سابق)
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS gender text;
