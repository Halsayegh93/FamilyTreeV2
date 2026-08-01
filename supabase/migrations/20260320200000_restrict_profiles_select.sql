-- تقييد قراءة جدول profiles: فقط الأعضاء المفعّلين يشوفون البيانات
-- Restrict profiles SELECT: only active members (member/supervisor/admin) can read data
-- المستخدم الجديد (pending أو بدون ملف) ما يشوف بيانات العائلة

-- حذف السياسة القديمة
DROP POLICY IF EXISTS "profiles_select_authenticated" ON public.profiles;

-- سياسة جديدة: المستخدم يشوف ملفه الشخصي فقط، أو كل الملفات إذا كان عضو مفعّل
CREATE POLICY "profiles_select_self_or_active" ON public.profiles
FOR SELECT
USING (
  -- يقدر يشوف ملفه الشخصي دائماً (مطلوب للتسجيل والتحقق)
  id = auth.uid()
  -- أو إذا كان عضو مفعّل (member/supervisor/admin) يشوف الكل
  OR public.current_user_role() IN ('member', 'supervisor', 'admin')
);
