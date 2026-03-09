-- جدول إعدادات التطبيق (صف واحد فقط)
CREATE TABLE IF NOT EXISTS app_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    news_requires_approval BOOLEAN NOT NULL DEFAULT true,
    allow_new_registrations BOOLEAN NOT NULL DEFAULT true,
    trial_enabled BOOLEAN NOT NULL DEFAULT true,
    maintenance_mode BOOLEAN NOT NULL DEFAULT false,
    max_devices_per_user INTEGER NOT NULL DEFAULT 3,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by UUID REFERENCES profiles(id)
);

-- إدخال الصف الافتراضي
INSERT INTO app_settings (id) VALUES ('00000000-0000-0000-0000-000000000001')
ON CONFLICT (id) DO NOTHING;

-- RLS: القراءة لجميع المستخدمين المسجلين
ALTER TABLE app_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can read app_settings"
    ON app_settings FOR SELECT
    TO authenticated
    USING (true);

-- الكتابة للأدمن فقط (role = 'admin')
CREATE POLICY "Admins can update app_settings"
    ON app_settings FOR UPDATE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE profiles.id = auth.uid()
            AND profiles.role = 'admin'
        )
    );
