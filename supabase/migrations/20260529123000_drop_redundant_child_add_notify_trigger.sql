-- ── إزالة الإشعار المزدوج عند إضافة ابن ─────────────────────────────────────
-- المشكلة: عند إضافة ابن يصل للمدير إشعاران:
--   ١) إشعار من DB trigger: "إضافة ابن جديد" (notify_admins_on_child_profile_insert)
--   ٢) إشعار من التطبيق:    "طلب إضافة ابن" (childAdd) أو "إضافة ابن جديد" (admin_edit_child_add)
--
-- التطبيق (iOS) يُرسل إشعاراً لكل إدراج profile فيه father_id:
--   • العضو العادي (AddChildSheet) → notifyAdminsWithPush(kind=child_add) + بيانات الموافقة
--   • المدير (AddSonByAdminSheet)  → notifyAdminsWithPush(kind=admin_edit_child_add)
-- وتطبيق الويب لا يحتوي على ميزة "إضافة ابن" للأعضاء (فقط تسجيل عضو من الإدارة
-- وهو father_id=NULL ولا يُفعّل هذا الـ trigger أصلاً).
--
-- لذا الـ trigger أصبح مكرّراً بالكامل. الحل: إسقاطه نهائياً.

DROP TRIGGER IF EXISTS profiles_notify_admins_child_add ON public.profiles;
DROP FUNCTION IF EXISTS public.notify_admins_on_child_profile_insert();
