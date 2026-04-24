-- Schedule weekly cleanup of stale/invalid device tokens via pg_cron + pg_net.
-- يشتغل كل أحد الساعة 3 صباحاً UTC، يستدعي edge function cleanup-tokens.

CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- إلغاء أي جدولة سابقة (idempotent)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cleanup-tokens-weekly') THEN
    PERFORM cron.unschedule('cleanup-tokens-weekly');
  END IF;
END $$;

-- جدولة أسبوعية: كل أحد 3 صباحاً
SELECT cron.schedule(
  'cleanup-tokens-weekly',
  '0 3 * * 0',
  $$
  SELECT net.http_post(
    url := 'https://poxyxsgvzwmnmewytsiw.supabase.co/functions/v1/cleanup-tokens',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body := '{}'::jsonb
  );
  $$
);
