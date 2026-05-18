-- إضافة حقل الرد الإداري على رسائل التواصل
-- admin_reply: نص الرد المكتوب من الإدارة
-- replied_at: وقت إرسال الرد
-- replied_by: المعرّف الـ uuid للإداري اللي رد

ALTER TABLE public.admin_requests
    ADD COLUMN IF NOT EXISTS admin_reply TEXT,
    ADD COLUMN IF NOT EXISTS replied_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS replied_by UUID REFERENCES public.profiles(id);

COMMENT ON COLUMN public.admin_requests.admin_reply IS
    'نص الرد الإداري على رسالة التواصل — يظهر للعضو في إشعار + إيميل';
COMMENT ON COLUMN public.admin_requests.replied_at IS
    'وقت إرسال الرد الإداري';
COMMENT ON COLUMN public.admin_requests.replied_by IS
    'الإداري اللي أرسل الرد';

-- فهرس للبحث السريع عن الرسائل اللي رُد عليها
CREATE INDEX IF NOT EXISTS idx_admin_requests_replied_at
    ON public.admin_requests (replied_at DESC)
    WHERE replied_at IS NOT NULL;
