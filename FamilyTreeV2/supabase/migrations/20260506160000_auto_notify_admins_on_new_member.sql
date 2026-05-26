-- ── Webhook داخلي: إشعار المدراء تلقائياً عند تسجيل عضو جديد ─────────────
-- عند إضافة profile جديد بـ role='pending'، يُدرج إشعار في جدول notifications
-- لكل أعضاء فريق الإدارة — يظهر تلقائياً في التطبيق عبر Realtime

-- ── الدالة ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_admins_on_new_pending_member()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    admin_id UUID;
    member_display TEXT;
BEGIN
    -- فقط للأعضاء الجدد بـ role='pending'
    IF NEW.role <> 'pending' OR NEW.status <> 'pending' THEN
        RETURN NEW;
    END IF;

    -- اسم العضو للعرض في الإشعار
    member_display := COALESCE(NEW.full_name, NEW.first_name, 'عضو جديد');

    -- إدراج إشعار لكل مدير/مراقب/مشرف/مالك
    FOR admin_id IN
        SELECT id FROM public.profiles
        WHERE role IN ('owner', 'admin', 'monitor', 'supervisor')
          AND status = 'active'
          AND id <> NEW.id
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
            'طلب انضمام جديد',
            member_display || ' يطلب الانضمام للشجرة',
            'join_request',
            NEW.id,
            false
        );
    END LOOP;

    RETURN NEW;
END;
$$;

-- ── الـ Trigger ───────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_notify_admins_new_pending_member ON public.profiles;

CREATE TRIGGER trg_notify_admins_new_pending_member
    AFTER INSERT ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.notify_admins_on_new_pending_member();
