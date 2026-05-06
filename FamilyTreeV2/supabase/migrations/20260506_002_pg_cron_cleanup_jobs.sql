-- ── pg_cron: مهام تنظيف تلقائية ───────────────────────────────────────────
-- يتطلب: Supabase Pro + تفعيل pg_cron من Dashboard → Extensions

CREATE EXTENSION IF NOT EXISTS pg_cron;

-- منح صلاحية جدولة المهام للـ postgres user
GRANT USAGE ON SCHEMA cron TO postgres;

-- ── ١. تنظيف جلسات الموقع القديمة (أكثر من ٣٠ يوم) ─────────────────────
-- يحذف web_sessions التي لم يُستخدم فيها منذ شهر
SELECT cron.schedule(
    'cleanup-old-web-sessions',
    '0 2 * * *',  -- كل يوم الساعة ٢ فجراً
    $$
        DELETE FROM web_sessions
        WHERE last_seen < NOW() - INTERVAL '30 days';
    $$
);

-- ── ٢. تنظيف الإشعارات المقروءة القديمة (أكثر من ٩٠ يوم) ───────────────
SELECT cron.schedule(
    'cleanup-old-read-notifications',
    '0 3 * * 0',  -- كل أحد الساعة ٣ فجراً
    $$
        DELETE FROM notifications
        WHERE is_read = true
          AND created_at < NOW() - INTERVAL '90 days';
    $$
);

-- ── ٣. تنظيف سجلات النشاط القديمة (أكثر من ١٨٠ يوم) ──────────────────
SELECT cron.schedule(
    'cleanup-old-user-timeline',
    '0 4 1 * *',  -- أول كل شهر الساعة ٤ فجراً
    $$
        DELETE FROM user_timeline
        WHERE created_at < NOW() - INTERVAL '180 days';
    $$
);

-- ── ٤. تنظيف device_tokens للأعضاء الغير نشطين (أكثر من ٦ أشهر) ────────
-- يحافظ على جدول device_tokens نظيف من tokens المنتهية
SELECT cron.schedule(
    'cleanup-inactive-device-tokens',
    '0 3 * * 1',  -- كل اثنين الساعة ٣ فجراً
    $$
        DELETE FROM device_tokens
        WHERE member_id IN (
            SELECT id FROM profiles
            WHERE last_active_at < NOW() - INTERVAL '180 days'
               OR last_active_at IS NULL
        );
    $$
);

-- ── ٥. أرشفة طلبات الانضمام المكتملة القديمة (أكثر من ٦٠ يوم) ──────────
SELECT cron.schedule(
    'cleanup-old-join-requests',
    '0 3 * * 3',  -- كل أربعاء الساعة ٣ فجراً
    $$
        DELETE FROM join_requests
        WHERE status IN ('approved', 'rejected')
          AND created_at < NOW() - INTERVAL '60 days';
    $$
);

-- ── للاطلاع على الجدول الزمني الحالي ────────────────────────────────────
-- SELECT * FROM cron.job;
-- ── لإلغاء مهمة ─────────────────────────────────────────────────────────
-- SELECT cron.unschedule('cleanup-old-web-sessions');
