-- استرجاع الإشعارات المحذوفة يوم ٢٠٢٦-١٠-٠٤
-- (طلب المالك: «امسح جميع الإشعارات من جميع المستخدمين» — مع سجل النشاط، بعد تأكيده)
--
-- الحذف حفظ نسخة كاملة أولاً في public.notifications_backup_20261004 (٢٥١١ صفاً،
-- RLS مفعّل وبلا صلاحية anon/authenticated). هذا الملف يرجعها كما كانت.
--
-- مهم: مشغّلات الإدراج تُطفأ أثناء الاسترجاع — وإلا trg_push_on_notification يرسل
-- ٢٥١١ إشعار دفع للأعضاء، وtrg_fanout_broadcast_notification يكرّر إشعارات «للجميع».

begin;

alter table public.notifications disable trigger trg_push_on_notification;
alter table public.notifications disable trigger trg_fanout_broadcast_notification;
alter table public.notifications disable trigger trg_admin_sender_as_administration;
alter table public.notifications disable trigger trg_notifications_fill_subject;

insert into public.notifications
select * from public.notifications_backup_20261004
on conflict (id) do nothing;

alter table public.notifications enable trigger trg_push_on_notification;
alter table public.notifications enable trigger trg_fanout_broadcast_notification;
alter table public.notifications enable trigger trg_admin_sender_as_administration;
alter table public.notifications enable trigger trg_notifications_fill_subject;

commit;
