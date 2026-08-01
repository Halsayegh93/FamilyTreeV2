-- إضافة عمود مصدر التسجيل واسم المستخدم
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS registration_platform TEXT DEFAULT 'ios',
  ADD COLUMN IF NOT EXISTS username TEXT;

-- فهرس على username للبحث السريع
CREATE UNIQUE INDEX IF NOT EXISTS profiles_username_idx ON profiles (username) WHERE username IS NOT NULL;
