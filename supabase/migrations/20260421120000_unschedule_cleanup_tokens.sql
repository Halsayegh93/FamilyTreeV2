-- إيقاف الجدولة الأسبوعية للتنظيف — المستخدم يشغّلها يدوياً من داخل التطبيق
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cleanup-tokens-weekly') THEN
    PERFORM cron.unschedule('cleanup-tokens-weekly');
  END IF;
END $$;
