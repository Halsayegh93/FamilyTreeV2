-- إصلاح سياسة قراءة الإشعارات
-- المشكلة: الإشعارات الإدارية (target_member_id = NULL) كانت مرئية لجميع الأعضاء
-- السبب: الشرط (target_member_id is null) يطبق على أي مستخدم مصادق
-- الحل: الإشعارات broadcast (null) تظهر للمدراء فقط، الإشعارات الشخصية للعضو المعني

drop policy if exists "notifications_select_target_or_all_or_moderator" on public.notifications;

create policy "notifications_select_target_or_all_or_moderator" on public.notifications
for select
using (
  -- إشعار شخصي — يراه العضو المعني فقط
  target_member_id = auth.uid()
  -- إشعار broadcast (إداري) — المدراء والمشرفون فقط
  or (
    target_member_id is null
    and public.current_user_role() in ('owner', 'admin', 'monitor', 'supervisor')
  )
);
