-- مُستخرَجة من سجل الإنتاج (supabase_migrations.schema_migrations)
-- كانت مطبَّقة على القاعدة لكن ملفها مفقود من المستودع.

-- تصحيح: «إرسال إشعار للجميع» (kind = admin_broadcast) يعتمد على صفّ واحد
-- بـ target_member_id = NULL ليصل الإشعار الفوري لكل الأعضاء عبر مُطلق الدفع.
-- تفريخه للمدراء فقط كان سيحرم بقية الأعضاء من الإشعار — فنستثنيه.
create or replace function public.fanout_broadcast_notification()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if new.target_member_id is null and coalesce(new.kind, '') <> 'admin_broadcast' then
    insert into public.notifications
      (target_member_id, title, body, kind, created_by, created_at, is_read,
       request_id, request_type, details)
    select p.id, new.title, new.body, new.kind, new.created_by,
           coalesce(new.created_at, timezone('utc', now())), false,
           new.request_id, new.request_type, new.details
    from public.profiles p
    where p.role in ('owner', 'admin', 'monitor', 'supervisor');
    return null;   -- صفّ تنبيهات الإدارة المشترك لا يُدرَج
  end if;
  return new;      -- البثّ العام يبقى صفاً واحداً ليصل للجميع
end;
$$;

-- إزالة النسخ التي وُلّدت بالخطأ من بثّ عام أثناء النقل السابق
delete from public.notifications n
where n.kind = 'admin_broadcast'
  and n.target_member_id is not null
  and exists (
    select 1 from public.notifications b
    where b.target_member_id is null
      and b.kind = 'admin_broadcast'
      and b.title = n.title and b.body = n.body
      and b.created_at = n.created_at
  );;
