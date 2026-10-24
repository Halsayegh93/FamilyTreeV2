-- «إدارة تواريخ الوفاة» لفترة معيّنة (طلب المالك ٢٠٢٦-١٠-٢٤): مفتاحان في app_config (قاعدة «من السيرفر» — تتغيّر بلا
-- بناء تطبيق). لم يُطبَّق — بانتظار موافقة المالك. التراجع: supabase/rollback/20261025110000_death_dates_campaign_config_rollback.sql
-- التجربة المحلية: cd supabase/tests/family_links && node death_dates_campaign_config.test.mjs
--   • death_dates_campaign (bool، افتراضي true): إبراز «إدارة تواريخ الوفاة» في «اليوم». false = يرجع مكانها «ذكرى الراحلين».
--   • death_dates_campaign_until (text، افتراضي ''): آخر يوم للحملة YYYY-MM-DD بتوقيت الكويت — فارغ = حتى تكتمل التواريخ.
-- القيم يقرؤها كل الأعضاء عبر app_config() (التطبيق يقرؤها للإدارة فقط)، والتعديل للمالك عبر set_app_config الموجودة
-- (من صفحة «إدارة تواريخ الوفاة» في الآيفون). الفحص trg_app_config_guard يتحقق من القيمتين والافتراضيين.
-- قبل تطبيقه: التطبيق يُظهر الحملة ما دام في التواريخ ناقص، وتعطّل أدوات الإيقاف عند المالك بملاحظة.

insert into public.app_config (key, value, default_value, kind, category, label_ar, help_ar, rules, is_public, sort)
values
  ('death_dates_campaign', 'true'::jsonb, 'true'::jsonb, 'bool', 'deaths',
   'إبراز «إدارة تواريخ الوفاة» في «اليوم»',
   'حملة استكمال تواريخ الوفاة في لوحة الإدارة — إيقافها يعيد مكانها «ذكرى الراحلين».',
   '{}'::jsonb, false, 40),
  ('death_dates_campaign_until', '""'::jsonb, '""'::jsonb, 'text', 'deaths',
   'آخر يوم لحملة تواريخ الوفاة',
   'بصيغة 2026-11-30 (توقيت الكويت). فارغ = حتى تكتمل التواريخ.',
   '{"pattern": "^$|^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$", "min_length": 0, "pattern_ar": "التاريخ بصيغة 2026-11-30 أو فارغ"}'::jsonb,
   false, 41)
on conflict (key) do nothing;
