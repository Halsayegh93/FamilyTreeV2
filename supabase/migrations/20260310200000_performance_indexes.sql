-- فهارس لتحسين أداء التطبيق مع 10,000 عضو

-- === PROFILES ===
CREATE INDEX IF NOT EXISTS idx_profiles_status ON profiles (status);
CREATE INDEX IF NOT EXISTS idx_profiles_status_role ON profiles (status, role);
CREATE INDEX IF NOT EXISTS idx_profiles_created_at ON profiles (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_profiles_full_name ON profiles USING btree (full_name);
CREATE INDEX IF NOT EXISTS idx_profiles_sort_order ON profiles (father_id, sort_order);

-- === NOTIFICATIONS ===
CREATE INDEX IF NOT EXISTS idx_notifications_target ON notifications (target_member_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON notifications (created_at DESC);

-- === NEWS ===
CREATE INDEX IF NOT EXISTS idx_news_author_id ON news (author_id);

-- === NEWS COMMENTS ===
CREATE INDEX IF NOT EXISTS idx_news_comments_created_at ON news_comments (news_id, created_at DESC);

-- === MEMBER GALLERY ===
CREATE INDEX IF NOT EXISTS idx_gallery_photos_created_at ON member_gallery_photos (created_at DESC);
