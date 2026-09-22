-- الإشعار العام لكل الأعضاء للمالك والمدير فقط (فحص الثغرات)
-- المراقب/المشرف كانوا يقدرون يدرجون admin_broadcast/app_update فيتفرّع لكل الأعضاء.
-- إشعاراتهم لفريق الإدارة (target=null بأنواع أخرى) والموجّهة لعضو تبقى كما هي.
drop policy if exists notifications_insert_moderator_or_self_scope on public.notifications;
create policy notifications_insert_moderator_or_self_scope on public.notifications
  for insert to authenticated
  with check (
    public.current_user_role() in ('owner', 'admin')
    or (public.current_user_role() in ('monitor', 'supervisor')
        and coalesce(kind, '') not in ('admin_broadcast', 'app_update'))
    or (target_member_id is not null
        and (target_member_id = auth.uid() or public.is_descendant_of_caller(target_member_id)))
  );
