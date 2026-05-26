-- ═══════════════════════════════════════════════════════════════════════════
-- إشعار المدراء عند طلب رفع جديد للأرشيف (يحتاج موافقة)
-- - يُطلق فقط عند insert بـ approval_status = 'pending'
-- - يُدرج إشعار لكل owner + admin
-- - الإدارة ترى الإشعار في تاب الإشعارات وتقدر تفتح الأرشيف لمراجعة وموافقة/رفض
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.notify_admins_on_archive_pending()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    admin_id UUID;
    uploader_name TEXT;
BEGIN
    -- فقط للعناصر المعلَّقة
    IF NEW.approval_status <> 'pending' THEN
        RETURN NEW;
    END IF;

    -- اسم الرافع للعرض في الإشعار
    SELECT COALESCE(full_name, first_name, 'عضو')
      INTO uploader_name
      FROM public.profiles
     WHERE id = NEW.uploaded_by;

    -- إدراج إشعار لكل owner + admin نشط (ما عدا الرافع نفسه)
    FOR admin_id IN
        SELECT id FROM public.profiles
         WHERE role IN ('owner', 'admin')
           AND status = 'active'
           AND id <> NEW.uploaded_by
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
            'طلب رفع جديد للأرشيف',
            uploader_name || ' يطلب رفع: ' || NEW.title,
            'archive_upload_request',
            NEW.uploaded_by,
            false
        );
    END LOOP;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_admins_archive_pending ON public.family_archive;

CREATE TRIGGER trg_notify_admins_archive_pending
    AFTER INSERT ON public.family_archive
    FOR EACH ROW
    EXECUTE FUNCTION public.notify_admins_on_archive_pending();
