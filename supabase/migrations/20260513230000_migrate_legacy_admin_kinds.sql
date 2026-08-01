-- ════════════════════════════════════════════════════════════════════════
-- نقل إشعارات إدارية بـkinds قديمة إلى الـkinds المنظّمة
-- لتظهر في تاب "المستجدات" بدل "إشعاراتي".
--
-- خلفية: قبل توحيد التصنيفات، الكود كان يستخدم:
--   • kind='admin_child_add'  → الصحيح 'admin_edit_child_add'
--   • kind='admin' للحذف      → الصحيح 'member_delete'
-- هذه الإشعارات عالقة في تاب "إشعاراتي" (لأنها ليست في completedActionKinds)
-- بينما يجب أن تكون في "المستجدات" كإجراءات منفّذة من المدير.
-- ════════════════════════════════════════════════════════════════════════

-- 1) إضافة ابن من المدير (kind قديم)
UPDATE public.notifications
SET kind = 'admin_edit_child_add'
WHERE kind = 'admin_child_add';

-- 2) حذف عضو (kind='admin' مع عنوان "حذف عضو")
--    نتأكد بالعنوان حتى لا نطال إشعارات admin أخرى لها معنى مختلف.
UPDATE public.notifications
SET kind = 'member_delete'
WHERE kind = 'admin'
  AND title = 'حذف عضو';
