-- مُستخرَجة من سجل الإنتاج (supabase_migrations.schema_migrations)
-- كانت مطبَّقة على القاعدة لكن ملفها مفقود من المستودع.

-- إشعارات الإدارة المشتركة (target_member_id IS NULL) كانت صفاً واحداً يراه كل
-- المدراء: حذفه أو تعليمه مقروءاً من أي مدير كان يؤثّر على الجميع.
-- الحل: تفريخ نسخة مستقلة لكل عضو إدارة، فيصير لكل عضو تحكمه الخاص.

create or replace function public.fanout_broadcast_notification()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if new.target_member_id is null then
    insert into public.notifications
      (target_member_id, title, body, kind, created_by, created_at, is_read,
       request_id, request_type, details)
    select p.id, new.title, new.body, new.kind, new.created_by,
           coalesce(new.created_at, timezone('utc', now())), false,
           new.request_id, new.request_type, new.details
    from public.profiles p
    where p.role in ('owner', 'admin', 'monitor', 'supervisor');
    return null;   -- لا يُدرَج الصف المشترك إطلاقاً
  end if;
  return new;
end;
$$;

drop trigger if exists trg_fanout_broadcast_notification on public.notifications;
create trigger trg_fanout_broadcast_notification
before insert on public.notifications
for each row execute function public.fanout_broadcast_notification();

-- تحويل الإشعارات المشتركة الحالية إلى نسخ فردية، مع تعطيل مؤقّت لمُطلق
-- الإشعارات الفورية حتى لا تنهال إشعارات على أجهزة المدراء أثناء النقل.
alter table public.notifications disable trigger trg_push_on_notification;
alter table public.notifications disable trigger trg_fanout_broadcast_notification;

insert into public.notifications
  (target_member_id, title, body, kind, created_by, created_at, is_read,
   request_id, request_type, details)
select p.id, n.title, n.body, n.kind, n.created_by, n.created_at, n.is_read,
       n.request_id, n.request_type, n.details
from public.notifications n
cross join public.profiles p
where n.target_member_id is null
  and p.role in ('owner', 'admin', 'monitor', 'supervisor');

alter table public.notifications enable trigger trg_push_on_notification;
alter table public.notifications enable trigger trg_fanout_broadcast_notification;;
