-- ── إزالة الإشعار المزدوج عند إضافة مشروع ───────────────────────────────────
-- المشكلة: عند إضافة مشروع من تطبيق iOS يصل للمدير إشعاران:
--   ١) إشعار من DB trigger:  "طلب مشروع جديد" (notify_admins_on_project_pending)
--   ٢) إشعار من التطبيق:      "مشروع جديد يحتاج موافقة" (notifyAdminsWithPush)
--
-- التطبيق (iOS) يُرسل إشعاراً مخصصاً + push + بيانات الموافقة السريعة لكل إدراج
-- في projects. أما تطبيق الويب فكان يعتمد على هذا الـ trigger فقط (لا يُرسل إشعاره).
--
-- الحل (باختيار المستخدم): إسقاط الـ trigger نهائياً، وجعل تطبيق الويب يُرسل
-- إشعاره بنفسه عند إضافة مشروع (per-admin rows مطابقة لما كان يفعله الـ trigger).
-- بهذا: iOS والويب كلاهما يُرسل إشعاراً واحداً فقط.

DROP TRIGGER IF EXISTS trg_notify_admins_project_pending ON public.projects;
DROP FUNCTION IF EXISTS public.notify_admins_on_project_pending();
