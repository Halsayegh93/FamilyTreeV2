-- التراجع عن 20261127140000_sentry_alert_ar: يحذف الدوال الثلاث وسجلّ الإرسال.
-- إشعارات `app_error` المرسلة تبقى (سجلّ) — احذفها يدوياً إن أردت: delete from public.notifications where kind = 'app_error';
drop function if exists public.sentry_alert_notify_owners(text, text);
drop function if exists public.sentry_alert_release(text);
drop function if exists public.sentry_alert_claim(text, int);
drop table if exists private.sentry_alert_log;
