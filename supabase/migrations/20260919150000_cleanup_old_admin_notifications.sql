-- تنظيف جرس فريق الإدارة (طلب المالك 2026-09-19):
--   حذف إشعارات الإدارة (owner / admin / monitor / supervisor) التي عمرها شهر فأكثر،
--   بعد نسخها احتياطياً — مثل تنظيف إشعارات الأعضاء (20260919120000).
--
-- التراجع (إرجاع المحذوف):
--   insert into public.notifications select * from public.notifications_admin_backup_20260919
--   on conflict do nothing;

create table if not exists public.notifications_admin_backup_20260919
  (like public.notifications including all);

-- الجدول الاحتياطي مقفل: RLS بلا سياسات = لا وصول إلا لمفتاح الخدمة
alter table public.notifications_admin_backup_20260919 enable row level security;

insert into public.notifications_admin_backup_20260919
select n.*
from public.notifications n
join public.profiles p on p.id = n.target_member_id
where p.role in ('owner', 'admin', 'monitor', 'supervisor')
  and n.created_at < now() - interval '1 month'
on conflict do nothing;

delete from public.notifications n
using public.profiles p
where p.id = n.target_member_id
  and p.role in ('owner', 'admin', 'monitor', 'supervisor')
  and n.created_at < now() - interval '1 month';
