-- التحديث الإجباري لكل منصة (طلب المالك)
--
-- أرقام البناء تختلف بين الآيفون (CFBundleVersion) والأندرويد (versionCode)،
-- فلكل منصة حدّ أدنى ورابط. أي نسخة أقل من الحد تُحجب بشاشة «حدّث التطبيق».
-- 0 = لا إجبار. force_update/latest_build القديمان يبقيان لنسخ الأندرويد المثبّتة
-- قبل هذا التعديل (تقرأهما هي فقط).
alter table public.app_settings
  add column if not exists ios_min_build     int  not null default 0,
  add column if not exists android_min_build int  not null default 0,
  add column if not exists ios_update_url     text,
  add column if not exists android_update_url text;
