-- =============================================================================
-- إصلاح حرج: سياسة SELECT للـ profiles ما تشمل owner و monitor
-- المالك والمراقب ما يقدرون يشوفون بيانات الأعضاء بدون هالإصلاح
-- =============================================================================

DROP POLICY IF EXISTS "profiles_select_self_or_active" ON public.profiles;
CREATE POLICY "profiles_select_self_or_active" ON public.profiles
FOR SELECT
USING (
  id = auth.uid()
  OR public.current_user_role() IN ('member', 'supervisor', 'monitor', 'admin', 'owner')
);
