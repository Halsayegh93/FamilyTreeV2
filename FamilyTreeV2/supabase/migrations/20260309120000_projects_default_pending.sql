-- تغيير القيمة الافتراضية لـ approval_status إلى pending
-- بحيث المشاريع الجديدة تحتاج موافقة الإدارة

ALTER TABLE public.projects
    ALTER COLUMN approval_status SET DEFAULT 'pending';
