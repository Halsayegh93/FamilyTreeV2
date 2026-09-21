-- لغة التطبيق الرسمية — يحددها المالك من «إعدادات التطبيق» (طلب المالك)
--
-- تُطبَّق على كل مستخدم لم يختر لغته بنفسه. من يغيّر اللغة من «الإعدادات»
-- تبقى لغته هو ولا تتأثر بتغيير اللغة الرسمية لاحقاً.

alter table public.app_settings
  add column if not exists default_language text not null default 'ar';

alter table public.app_settings
  drop constraint if exists app_settings_default_language_check;

alter table public.app_settings
  add constraint app_settings_default_language_check
  check (default_language in ('ar', 'en'));
