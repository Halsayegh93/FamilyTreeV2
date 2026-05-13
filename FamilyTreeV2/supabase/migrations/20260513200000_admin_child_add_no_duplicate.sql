-- ════════════════════════════════════════════════════════════════════════
-- إصلاح: trigger إضافة الابن السيرفري كان يكرّر الإشعار للمدراء
--
-- المشكلة: notify_admins_on_child_profile_insert() كان يرسل إشعار
-- بـkind='child_add' (طلب معلّق) لكل profile جديد فيه father_id.
-- لمّا المدير يضيف ابن:
--   1. iOS يرسل إشعار kind='admin_edit_child_add' → "المستجدات" ✓
--   2. الـtrigger يرسل إشعار kind='child_add' → "إشعاراتي" ❌ (تكرار)
--
-- الإصلاح:
--   • نتخطّى الـtrigger لو المُضيف (auth.uid()) مدير/مالك/مراقب/مشرف
--     (هذا يعني المدير يضيف بنفسه — iOS أصلاً يرسل admin_edit_child_add)
--   • للمستخدم العادي اللي يطلب إضافة ابن: الـtrigger يفعّل كـbackup
--     مع kind='child_add' (طلب معلّق للمراجعة) كما كان
-- ════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.notify_admins_on_child_profile_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  admin_profile_id uuid;
  title_text text;
  body_text text;
  inserter_role text;
BEGIN
  -- نتخطّى لو ما عنده father_id (ليس ابناً مرتبطاً)
  IF NEW.father_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- نتخطّى لو المُضيف مدير/مراقب/مشرف/مالك — iOS أصلاً يرسل
  -- إشعار admin_edit_child_add الذي يظهر في تاب "المستجدات"
  SELECT role INTO inserter_role
  FROM public.profiles
  WHERE id = auth.uid()
  LIMIT 1;

  IF inserter_role IN ('owner', 'admin', 'monitor', 'supervisor') THEN
    RETURN NEW;
  END IF;

  -- المستخدم العادي يضيف ابن — backup notification للمدراء (طلب مراجعة)
  title_text := 'إضافة ابن جديد';
  body_text := format('تمت إضافة ابن جديد في الشجرة: %s', COALESCE(NEW.full_name, NEW.first_name, 'عضو جديد'));

  FOR admin_profile_id IN
    SELECT p.id
    FROM public.profiles p
    WHERE p.role = 'admin'
  LOOP
    INSERT INTO public.notifications (
      target_member_id,
      title,
      body,
      kind,
      created_by
    ) VALUES (
      admin_profile_id,
      title_text,
      body_text,
      'child_add',
      NEW.father_id
    );
  END LOOP;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.notify_admins_on_child_profile_insert() IS
  'إشعار المدراء عند إضافة ابن جديد — يتخطّى عمليات المدراء (iOS يرسل admin_edit_child_add بنفسه)';
