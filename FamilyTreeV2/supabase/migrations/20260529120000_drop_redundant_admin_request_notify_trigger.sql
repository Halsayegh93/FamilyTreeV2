-- ── إزالة الإشعار المزدوج عند إنشاء طلب إداري ───────────────────────────────
-- المشكلة: عند تغيير رقم الهاتف (أو الاسم/تعديل الشجرة...) يصل للمدير إشعاران:
--   ١) إشعار عام من DB trigger:  "طلب إداري جديد" (notify_admins_on_admin_request)
--   ٢) إشعار دقيق من التطبيق:     "طلب تغيير رقم الهاتف" (notifyAdminsWithPush)
--
-- التطبيق (iOS) يُرسل إشعاراً مخصصاً + push + بيانات الموافقة السريعة (request_id/type)
-- لكل إدراج في admin_requests، وتطبيق الويب لا يُدرج في admin_requests مباشرة،
-- لذا الـ trigger أصبح مكرّراً بالكامل ويُنتج الإشعار الثاني الزائد.
--
-- الحل: إسقاط الـ trigger والدالة المرتبطة به نهائياً.

DROP TRIGGER IF EXISTS admin_requests_notify_admins ON public.admin_requests;
DROP FUNCTION IF EXISTS public.notify_admins_on_admin_request();
