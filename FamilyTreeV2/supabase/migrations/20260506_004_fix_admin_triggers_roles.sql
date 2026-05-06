-- ── إصلاح استهداف أدوار الإدارة في الـ Triggers القديمة ────────────────────
-- المشكلة: الـ triggers القديمة كانت تُرسل الإشعارات لـ role='admin' فقط
-- وتُفوّت: owner, monitor, supervisor — وكلهم يملكون صلاحية الدخول للوحة الإدارة

-- ── ١. إصلاح: إشعار المدراء عند إنشاء طلب إداري جديد ──────────────────────
CREATE OR REPLACE FUNCTION public.notify_admins_on_admin_request()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    admin_profile_id UUID;
    requester_name   TEXT;
    title_text       TEXT;
    body_text        TEXT;
BEGIN
    IF COALESCE(NEW.status, '') <> 'pending' THEN
        RETURN NEW;
    END IF;

    SELECT p.full_name INTO requester_name
    FROM public.profiles p
    WHERE p.id = NEW.member_id;

    requester_name := COALESCE(NULLIF(TRIM(requester_name), ''), 'عضو');
    title_text := 'طلب إداري جديد';
    body_text  := FORMAT('%s أرسل طلباً جديداً (%s) ويحتاج مراجعة الإدارة.', requester_name, NEW.request_type);

    FOR admin_profile_id IN
        SELECT p.id FROM public.profiles p
        WHERE p.role IN ('owner', 'admin', 'monitor', 'supervisor')
          AND p.status = 'active'
          AND p.id <> COALESCE(NEW.requester_id, NEW.member_id)
    LOOP
        INSERT INTO public.notifications (target_member_id, title, body, kind, created_by)
        VALUES (admin_profile_id, title_text, body_text, 'admin_request', NEW.requester_id);
    END LOOP;

    RETURN NEW;
END;
$$;

-- ── ٢. إصلاح: إشعار المدراء عند إضافة ابن في الشجرة ─────────────────────
CREATE OR REPLACE FUNCTION public.notify_admins_on_child_profile_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    admin_profile_id UUID;
    title_text       TEXT;
    body_text        TEXT;
BEGIN
    IF NEW.father_id IS NULL THEN
        RETURN NEW;
    END IF;

    title_text := 'إضافة ابن جديد';
    body_text  := FORMAT('تمت إضافة ابن جديد في الشجرة: %s', COALESCE(NEW.full_name, NEW.first_name, 'عضو جديد'));

    FOR admin_profile_id IN
        SELECT p.id FROM public.profiles p
        WHERE p.role IN ('owner', 'admin', 'monitor', 'supervisor')
          AND p.status = 'active'
          AND p.id <> COALESCE(NEW.father_id, '00000000-0000-0000-0000-000000000000'::UUID)
    LOOP
        INSERT INTO public.notifications (target_member_id, title, body, kind, created_by)
        VALUES (admin_profile_id, title_text, body_text, 'child_add', NEW.father_id);
    END LOOP;

    RETURN NEW;
END;
$$;

-- ── ٣. إصلاح: إشعار المدراء عند تعارض رقم في التسجيل ───────────────────
CREATE OR REPLACE FUNCTION public.free_phone_for_reregistration(
    p_phone          TEXT,
    p_new_member_id  UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_normalized  TEXT;
    v_old_id      UUID;
BEGIN
    v_normalized := REGEXP_REPLACE(TRIM(p_phone), '[^0-9+]', '', 'g');

    SELECT id INTO v_old_id
    FROM public.profiles
    WHERE phone_number = v_normalized
      AND id <> p_new_member_id
    LIMIT 1;

    IF v_old_id IS NOT NULL THEN
        UPDATE public.profiles
        SET phone_number = NULL
        WHERE id = v_old_id;

        INSERT INTO public.notifications (target_member_id, title, body, kind, created_by)
        SELECT
            p.id,
            'تعارض رقم عند التسجيل',
            FORMAT('الرقم %s كان مرتبطاً بعضو في الشجرة وتم تحريره للتسجيل الجديد. يُرجى مراجعة الطلب وإجراء الدمج إذا لزم.', v_normalized),
            'admin_request',
            p_new_member_id
        FROM public.profiles p
        WHERE p.role IN ('owner', 'admin', 'monitor', 'supervisor')
          AND p.status = 'active';
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.free_phone_for_reregistration(TEXT, UUID) TO authenticated;

-- ── ٤. إصلاح: تغيير kind في trigger التسجيل الجديد لـ 'link_request' ──────
-- كان 'join_request' الذي ليس له تصميم في NotificationsCenterView
-- 'link_request' له أيقونة وألوان معرّفة في التطبيق
CREATE OR REPLACE FUNCTION public.notify_admins_on_new_pending_member()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    admin_id       UUID;
    member_display TEXT;
BEGIN
    IF NEW.role <> 'pending' OR NEW.status <> 'pending' THEN
        RETURN NEW;
    END IF;

    member_display := COALESCE(NEW.full_name, NEW.first_name, 'عضو جديد');

    FOR admin_id IN
        SELECT id FROM public.profiles
        WHERE role IN ('owner', 'admin', 'monitor', 'supervisor')
          AND status = 'active'
          AND id <> NEW.id
    LOOP
        INSERT INTO public.notifications (
            target_member_id, title, body, kind, created_by, is_read
        ) VALUES (
            admin_id,
            'طلب انضمام جديد',
            member_display || ' يطلب الانضمام للشجرة',
            'link_request',
            NEW.id,
            false
        );
    END LOOP;

    RETURN NEW;
END;
$$;
