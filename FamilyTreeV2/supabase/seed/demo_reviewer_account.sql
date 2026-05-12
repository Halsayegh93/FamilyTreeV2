-- حساب تجريبي للمراجعين (Apple Review / مختبرين خارجيين)
-- استخدمه مع رقم Test في Supabase Auth → Phone Provider
--
-- الخطوات:
-- 1) Supabase Dashboard → Authentication → Providers → Phone → Test (OTP)
--    أضف: Phone = +96550000099, OTP = 123456
-- 2) شغّل هذا الـ SQL من Supabase Dashboard → SQL Editor
-- 3) أعطِ المراجع:
--      Country: Kuwait (+965)
--      Phone:   50000099
--      OTP:     123456

-- تنبيه: لازم أولاً تكون أنشأت auth.user بالرقم +96550000099
-- (يصير تلقائياً أول مرة يحاول المراجع يدخل، أو سوّه يدوياً من Auth → Users)

-- استبدل DEMO_USER_UUID بالـ UUID اللي يطلع لك في auth.users بعد إنشاء المستخدم
DO $$
DECLARE
  demo_uid uuid;
BEGIN
  SELECT id INTO demo_uid FROM auth.users WHERE phone = '+96550000099' LIMIT 1;
  IF demo_uid IS NULL THEN
    RAISE NOTICE 'auth.user للرقم +96550000099 غير موجود — سجّل دخول مرة بالـ Test OTP أولاً لإنشائه';
    RETURN;
  END IF;

  INSERT INTO public.profiles (
    id, full_name, first_name, phone_number,
    birth_date, role, status,
    is_deceased, is_married, is_hidden_from_tree,
    gender, sort_order, created_at
  ) VALUES (
    demo_uid,
    'حساب تجريبي للمراجعين',
    'تجريبي',
    '+96550000099',
    '1990-01-01',
    'member',
    'active',
    false,
    false,
    true,        -- مخفي من الشجرة
    'male',
    9999,
    now()
  )
  ON CONFLICT (id) DO UPDATE SET
    full_name = EXCLUDED.full_name,
    role = EXCLUDED.role,
    status = EXCLUDED.status,
    is_hidden_from_tree = EXCLUDED.is_hidden_from_tree;

  RAISE NOTICE 'تم إنشاء/تحديث الحساب التجريبي: %', demo_uid;
END $$;
