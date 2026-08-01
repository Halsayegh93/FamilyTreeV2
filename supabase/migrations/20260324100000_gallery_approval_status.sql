-- إضافة حالة الموافقة لصور المعرض
-- الصور الحالية تبقى approved، الجديدة من الأعضاء تكون pending

ALTER TABLE member_gallery_photos
ADD COLUMN IF NOT EXISTS approval_status text DEFAULT 'approved';

-- فهرس للبحث السريع عن الصور المعلقة
CREATE INDEX IF NOT EXISTS idx_gallery_approval_status
ON member_gallery_photos (approval_status)
WHERE approval_status = 'pending';

-- تحديث سياسة القراءة: الأعضاء يشوفون فقط المعتمدة + صورهم المعلقة
DROP POLICY IF EXISTS "gallery_select" ON member_gallery_photos;
CREATE POLICY "gallery_select" ON member_gallery_photos
FOR SELECT USING (
    approval_status = 'approved'
    OR created_by = auth.uid()
    OR public.current_user_role() IN ('owner', 'admin', 'supervisor')
);
