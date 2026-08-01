-- ═══════════════════════════════════════════════════════════════════════════
-- إشعار المدراء عند طلب مشروع جديد (يحتاج موافقة)
-- - يُطلق فقط عند insert بـ approval_status = 'pending'
-- - يُدرج إشعار لكل owner + admin
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.notify_admins_on_project_pending()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    admin_id UUID;
    owner_display TEXT;
BEGIN
    -- فقط للمشاريع المعلَّقة
    IF NEW.approval_status <> 'pending' THEN
        RETURN NEW;
    END IF;

    -- اسم صاحب المشروع
    owner_display := COALESCE(NEW.owner_name, 'عضو');

    -- إدراج إشعار لكل owner + admin نشط (ما عدا صاحب المشروع نفسه)
    FOR admin_id IN
        SELECT id FROM public.profiles
         WHERE role IN ('owner', 'admin')
           AND status = 'active'
           AND id <> NEW.owner_id
    LOOP
        INSERT INTO public.notifications (
            target_member_id,
            title,
            body,
            kind,
            created_by,
            is_read
        ) VALUES (
            admin_id,
            'طلب مشروع جديد',
            owner_display || ' يطلب إضافة: ' || NEW.title,
            'project_request',
            NEW.owner_id,
            false
        );
    END LOOP;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_admins_project_pending ON public.projects;

CREATE TRIGGER trg_notify_admins_project_pending
    AFTER INSERT ON public.projects
    FOR EACH ROW
    EXECUTE FUNCTION public.notify_admins_on_project_pending();
