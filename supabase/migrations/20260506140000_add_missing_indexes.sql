-- ── Indexes ناقصة ──────────────────────────────────────────────────────────
-- notifications: كل مستخدم يجلب إشعاراته بـ target_member_id — بدون index = full table scan
CREATE INDEX IF NOT EXISTS idx_notifications_member_read
    ON notifications(target_member_id, is_read, created_at DESC);

-- diwaniyas: fetchPendingDiwaniyas يفلتر بـ approval_status = 'pending'
CREATE INDEX IF NOT EXISTS idx_diwaniyas_approval_status
    ON diwaniyas(approval_status);

-- profiles: queries كثيرة تفلتر بـ status = 'active' / 'pending' / 'frozen'
CREATE INDEX IF NOT EXISTS idx_profiles_status
    ON profiles(status);

-- admin_requests: كل نوع طلب يُجلب بـ request_type منفصل
CREATE INDEX IF NOT EXISTS idx_admin_requests_type_status
    ON admin_requests(request_type, status);
