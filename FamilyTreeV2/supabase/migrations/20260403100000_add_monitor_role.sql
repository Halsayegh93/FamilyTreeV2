-- =============================================================================
-- إضافة دور المراقب (monitor) وتحديث صلاحيات الحذف للمدير
-- =============================================================================

-- 1. تحديث CHECK constraint ليشمل monitor
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_role_check
  CHECK (role IN ('pending', 'member', 'supervisor', 'monitor', 'admin', 'owner'));

-- 2. تحديث trigger حماية الأدوار — إضافة المراقب
CREATE OR REPLACE FUNCTION public.prevent_role_self_promotion()
RETURNS trigger AS $$
DECLARE
  caller_role text;
BEGIN
  caller_role := public.current_user_role();

  -- لا أحد يقدر يغير دور المالك
  IF OLD.role = 'owner' AND NEW.role != 'owner' THEN
    NEW.role := OLD.role;
    RETURN NEW;
  END IF;

  -- لا أحد يقدر يترقى لمالك عبر التطبيق
  IF NEW.role = 'owner' AND OLD.role != 'owner' THEN
    NEW.role := OLD.role;
    RETURN NEW;
  END IF;

  -- تغيير الدور أو الحالة
  IF OLD.role IS DISTINCT FROM NEW.role OR OLD.status IS DISTINCT FROM NEW.status THEN
    IF caller_role = 'owner' THEN
      -- المالك يقدر يسوي كل شي
      NULL;
    ELSIF caller_role = 'admin' THEN
      -- المدير ما يقدر يغير أدوار
      IF OLD.role IS DISTINCT FROM NEW.role THEN
        NEW.role := OLD.role;
      END IF;
    ELSE
      -- المراقب والمشرف والعضو ما يقدرون يغيرون دور أو حالة
      NEW.role := OLD.role;
      NEW.status := OLD.status;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. تحديث RLS policies لتشمل monitor

-- === profiles ===
DROP POLICY IF EXISTS "profiles_update_self_or_moderator" ON public.profiles;
CREATE POLICY "profiles_update_self_or_moderator" ON public.profiles
FOR UPDATE
USING (
  id = auth.uid()
  OR public.current_user_role() IN ('supervisor', 'monitor', 'admin', 'owner')
)
WITH CHECK (
  id = auth.uid()
  OR public.current_user_role() IN ('supervisor', 'monitor', 'admin', 'owner')
);

-- === profiles delete — المدير والمالك فقط ===
DROP POLICY IF EXISTS "profiles_delete_admin_or_owner" ON public.profiles;
CREATE POLICY "profiles_delete_admin_or_owner" ON public.profiles
FOR DELETE
USING (public.current_user_role() IN ('admin', 'owner'));

-- === news ===
DROP POLICY IF EXISTS "news_select_approved_or_owner_or_moderator" ON public.news;
CREATE POLICY "news_select_approved_or_owner_or_moderator" ON public.news
FOR SELECT
USING (
  approval_status = 'approved'
  OR author_id = auth.uid()
  OR public.current_user_role() IN ('supervisor', 'monitor', 'admin', 'owner')
);

DROP POLICY IF EXISTS "news_update_moderator" ON public.news;
CREATE POLICY "news_update_moderator" ON public.news
FOR UPDATE
USING (public.current_user_role() IN ('supervisor', 'monitor', 'admin', 'owner'))
WITH CHECK (public.current_user_role() IN ('supervisor', 'monitor', 'admin', 'owner'));

-- === admin_requests ===
DROP POLICY IF EXISTS "admin_requests_select_moderator_or_owner" ON public.admin_requests;
CREATE POLICY "admin_requests_select_moderator_or_owner" ON public.admin_requests
FOR SELECT
USING (
  requester_id = auth.uid()
  OR member_id = auth.uid()
  OR public.current_user_role() IN ('supervisor', 'monitor', 'admin', 'owner')
);

DROP POLICY IF EXISTS "admin_requests_update_moderator" ON public.admin_requests;
CREATE POLICY "admin_requests_update_moderator" ON public.admin_requests
FOR UPDATE
USING (public.current_user_role() IN ('supervisor', 'monitor', 'admin', 'owner'))
WITH CHECK (public.current_user_role() IN ('supervisor', 'monitor', 'admin', 'owner'));

-- === diwaniyas ===
DROP POLICY IF EXISTS "diwaniya_select_approved_or_owner_or_moderator" ON public.diwaniyas;
CREATE POLICY "diwaniya_select_approved_or_owner_or_moderator" ON public.diwaniyas
FOR SELECT
USING (
  approval_status = 'approved'
  OR owner_id = auth.uid()
  OR public.current_user_role() IN ('supervisor', 'monitor', 'admin', 'owner')
);

DROP POLICY IF EXISTS "diwaniya_update_moderator" ON public.diwaniyas;
CREATE POLICY "diwaniya_update_moderator" ON public.diwaniyas
FOR UPDATE
USING (public.current_user_role() IN ('supervisor', 'monitor', 'admin', 'owner'))
WITH CHECK (public.current_user_role() IN ('supervisor', 'monitor', 'admin', 'owner'));

-- === notifications ===
DROP POLICY IF EXISTS "notifications_select_target_or_all_or_moderator" ON public.notifications;
CREATE POLICY "notifications_select_target_or_all_or_moderator" ON public.notifications
FOR SELECT
USING (
  target_member_id IS NULL
  OR target_member_id = auth.uid()
  OR public.current_user_role() IN ('supervisor', 'monitor', 'admin', 'owner')
);

DROP POLICY IF EXISTS "notifications_insert_moderator" ON public.notifications;
CREATE POLICY "notifications_insert_moderator" ON public.notifications
FOR INSERT
WITH CHECK (public.current_user_role() IN ('supervisor', 'monitor', 'admin', 'owner'));

-- === device_tokens ===
DROP POLICY IF EXISTS "device_tokens_select_self_or_moderator" ON public.device_tokens;
CREATE POLICY "device_tokens_select_self_or_moderator" ON public.device_tokens
FOR SELECT
USING (
  member_id = auth.uid()
  OR public.current_user_role() IN ('supervisor', 'monitor', 'admin', 'owner')
);

-- === member_gallery_photos ===
DROP POLICY IF EXISTS "member_gallery_insert_self_or_moderator" ON public.member_gallery_photos;
CREATE POLICY "member_gallery_insert_self_or_moderator" ON public.member_gallery_photos
FOR INSERT
WITH CHECK (
  member_id = auth.uid()
  OR public.current_user_role() IN ('supervisor', 'monitor', 'admin', 'owner')
);

DROP POLICY IF EXISTS "member_gallery_delete_self_or_moderator" ON public.member_gallery_photos;
CREATE POLICY "member_gallery_delete_self_or_moderator" ON public.member_gallery_photos
FOR DELETE
USING (
  member_id = auth.uid()
  OR public.current_user_role() IN ('supervisor', 'monitor', 'admin', 'owner')
);

-- === projects ===
DROP POLICY IF EXISTS "projects_update_owner_or_mod" ON public.projects;
CREATE POLICY "projects_update_owner_or_mod" ON public.projects
FOR UPDATE
USING (
  owner_id = auth.uid()
  OR public.current_user_role() IN ('supervisor', 'monitor', 'admin', 'owner')
);

DROP POLICY IF EXISTS "projects_delete_owner_or_mod" ON public.projects;
CREATE POLICY "projects_delete_owner_or_mod" ON public.projects
FOR DELETE
USING (
  owner_id = auth.uid()
  OR public.current_user_role() IN ('supervisor', 'monitor', 'admin', 'owner')
);

-- === stories ===
DROP POLICY IF EXISTS "stories_update_moderator" ON public.stories;
CREATE POLICY "stories_update_moderator" ON public.stories
FOR UPDATE
USING (
  author_id = auth.uid()
  OR public.current_user_role() IN ('supervisor', 'monitor', 'admin', 'owner')
)
WITH CHECK (
  author_id = auth.uid()
  OR public.current_user_role() IN ('supervisor', 'monitor', 'admin', 'owner')
);
