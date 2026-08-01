-- =====================================================
-- إصلاح RLS للجداول الناقصة
-- join_requests و user_timeline
-- =====================================================

-- ===== join_requests =====
ALTER TABLE IF EXISTS public.join_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "join_requests_select_moderator" ON public.join_requests
  FOR SELECT USING (
    current_user_role() IN ('supervisor','monitor','admin','owner')
  );

CREATE POLICY "join_requests_insert_authenticated" ON public.join_requests
  FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "join_requests_update_moderator" ON public.join_requests
  FOR UPDATE USING (
    current_user_role() IN ('supervisor','monitor','admin','owner')
  );

CREATE POLICY "join_requests_delete_admin" ON public.join_requests
  FOR DELETE USING (
    current_user_role() IN ('admin','owner')
  );

-- ===== user_timeline =====
ALTER TABLE IF EXISTS public.user_timeline ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_timeline_select_self" ON public.user_timeline
  FOR SELECT USING (
    user_id = auth.uid() OR current_user_role() IN ('admin','owner')
  );

CREATE POLICY "user_timeline_insert_authenticated" ON public.user_timeline
  FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
