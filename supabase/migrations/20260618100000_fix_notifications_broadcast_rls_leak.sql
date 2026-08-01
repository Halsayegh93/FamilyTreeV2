-- إصلاح تسريب إشعارات «المستجدات» (broadcast) للأعضاء العاديين.
--
-- المشكلة: migration 20260506100000 أعاد كتابة سياسة القراءة بالشكل:
--     target_member_id is null OR target_member_id = auth.uid() OR role in (...)
-- وبما أن (target_member_id is null) فرع OR غير مشروط، صار أي عضو مصادَق
-- يقدر يقرأ كل إشعارات البث الإدارية عبر الـ API بغضّ النظر عن دوره.
--
-- الإصلاح: نستعيد المنطق الآمن من 20260423150000 — إشعار البث (null)
-- يُقرأ للمشرفين فقط (owner/admin/monitor/supervisor)، والإشعار الشخصي
-- لصاحبه فقط. هذا يغلق أيضاً ثغرة «المدير السابق»: الدور يُحسب لحظياً عبر
-- current_user_role()، فبمجرد تنزيل العضو لـ member يفقد رؤية البث فوراً.

drop policy if exists "notifications_select_target_or_all_or_moderator" on public.notifications;

create policy "notifications_select_target_or_all_or_moderator" on public.notifications
for select
using (
  -- إشعار شخصي — يراه العضو المعني فقط
  target_member_id = auth.uid()
  -- إشعار broadcast (إداري/المستجدات) — المشرفون فقط
  or (
    target_member_id is null
    and public.current_user_role() in ('owner', 'admin', 'monitor', 'supervisor')
  )
);
