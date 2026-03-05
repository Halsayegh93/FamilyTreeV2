-- إصلاح القيم الفارغة في جدول profiles
-- Fix NULL values in profiles table to ensure all members appear in the tree

-- إصلاح role: أي عضو بدون role يصير member
UPDATE public.profiles SET role = 'member' WHERE role IS NULL;

-- إصلاح status: أي عضو بدون status يصير active
UPDATE public.profiles SET status = 'active' WHERE status IS NULL;

-- إصلاح is_hidden_from_tree: أي عضو بدون قيمة يظهر بالشجرة
UPDATE public.profiles SET is_hidden_from_tree = false WHERE is_hidden_from_tree IS NULL;

-- إصلاح is_deceased: أي عضو بدون قيمة يُعتبر حي
UPDATE public.profiles SET is_deceased = false WHERE is_deceased IS NULL;

-- إصلاح is_married: أي عضو بدون قيمة
UPDATE public.profiles SET is_married = false WHERE is_married IS NULL;

-- إصلاح is_phone_hidden
UPDATE public.profiles SET is_phone_hidden = false WHERE is_phone_hidden IS NULL;

-- إصلاح sort_order
UPDATE public.profiles SET sort_order = 0 WHERE sort_order IS NULL;

-- إصلاح first_name: استخدام أول كلمة من full_name إذا first_name فارغ
UPDATE public.profiles SET first_name = split_part(full_name, ' ', 1) WHERE first_name IS NULL AND full_name IS NOT NULL;
UPDATE public.profiles SET first_name = 'بدون اسم' WHERE first_name IS NULL;

-- إصلاح full_name: استخدام first_name إذا full_name فارغ
UPDATE public.profiles SET full_name = first_name WHERE full_name IS NULL AND first_name IS NOT NULL;
UPDATE public.profiles SET full_name = 'بدون اسم' WHERE full_name IS NULL;

-- إصلاح bio_json
UPDATE public.profiles SET bio_json = '[]'::jsonb WHERE bio_json IS NULL;

-- إصلاح created_at
UPDATE public.profiles SET created_at = timezone('utc', now()) WHERE created_at IS NULL;
