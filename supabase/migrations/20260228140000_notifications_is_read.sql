-- إضافة عمود is_read للإشعارات
ALTER TABLE public.notifications
ADD COLUMN IF NOT EXISTS is_read boolean NOT NULL DEFAULT false;
