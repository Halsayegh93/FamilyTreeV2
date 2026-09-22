-- تنظيف جرس الأعضاء العاديين (طلب المالك 2026-09-19):
--   حذف إشعارات الأعضاء العاديين (member / pending) التي عمرها شهر فأكثر،
--   بعد نسخها احتياطياً. الإشعارات الجديدة تصل كالمعتاد — لا منع.
--   إشعارات الإدارة (owner / admin / monitor / supervisor) لا تُمسّ.
--
-- التراجع (إرجاع المحذوف):
--   insert into public.notifications select * from public.notifications_member_backup_20260919
--   on conflict do nothing;

-- ── نسخة احتياطية ثم حذف إشعارات الأعضاء الأقدم من شهر ──────────────────
create table if not exists public.notifications_member_backup_20260919
  (like public.notifications including all);

-- الجدول الاحتياطي مقفل: RLS بلا سياسات = لا وصول إلا لمفتاح الخدمة
alter table public.notifications_member_backup_20260919 enable row level security;

insert into public.notifications_member_backup_20260919
select n.*
from public.notifications n
join public.profiles p on p.id = n.target_member_id
where p.role in ('member', 'pending')
  and n.created_at < now() - interval '1 month'
on conflict do nothing;

delete from public.notifications n
using public.profiles p
where p.id = n.target_member_id
  and p.role in ('member', 'pending')
  and n.created_at < now() - interval '1 month';

-- ── إشعار من عضو إدارة إلى عضو عادي يظهر باسم «الإدارة» ─────────────────────
-- (طلب المالك) يسري على iOS وأندرويد والموقع: إعجاب/تعليق من أي عضو في فريق
-- الإدارة على خبر عضو عادي → النص «الإدارة …» بدل اسم الشخص.
create or replace function public.admin_sender_as_administration()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if new.kind in ('news_like', 'news_comment')
     and new.created_by is not null
     and new.target_member_id is not null
     and exists (select 1 from public.profiles p
                 where p.id = new.created_by
                   and p.role in ('owner', 'admin', 'monitor', 'supervisor'))
     and exists (select 1 from public.profiles p
                 where p.id = new.target_member_id
                   and p.role in ('member', 'pending')) then
    new.body := case new.kind
                  when 'news_like' then 'الإدارة أعجبت بخبرك'
                  else 'الإدارة علّقت على خبرك'
                end;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_admin_sender_as_administration on public.notifications;
create trigger trg_admin_sender_as_administration
before insert on public.notifications
for each row execute function public.admin_sender_as_administration();
