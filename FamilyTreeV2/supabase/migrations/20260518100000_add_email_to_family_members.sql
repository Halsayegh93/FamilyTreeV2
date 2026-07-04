-- إضافة عمود email لجدول profiles (يمثّل أعضاء العائلة)
-- اختياري، nullable — يستخدم لإشعارات الإيميل (تغيير الدور، التجميد، إلخ)
-- خاص بصاحب الحساب — لا يظهر للأعضاء الآخرين

ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS email TEXT;
-- فهرس للبحث السريع (case-insensitive)
CREATE INDEX IF NOT EXISTS idx_profiles_email_lower
    ON public.profiles ((LOWER(email)))
    WHERE email IS NOT NULL;
COMMENT ON COLUMN public.profiles.email IS
    'إيميل العضو الاختياري — لاستقبال إشعارات الدور والحالة. خاص ولا يُعرض للآخرين.';
