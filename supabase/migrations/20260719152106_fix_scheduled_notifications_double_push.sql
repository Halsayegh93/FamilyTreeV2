-- مُستخرَجة من سجل الإنتاج (supabase_migrations.schema_migrations)
-- كانت مطبَّقة على القاعدة لكن ملفها مفقود من المستودع.

-- إصلاح تكرار الدفع للإشعارات المجدولة:
-- كانت الدالة تُدرج في notifications (فيشتغل trg_push_on_notification → دفعة) وكمان تنادي
-- push-on-notification يدويًا (دفعة ثانية). نحذف النداء اليدوي ونعتمد على التريغر — مسار واحد.
create or replace function public.dispatch_due_scheduled_notifications()
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
    rec record;
    mid uuid;
begin
    for rec in
        select * from public.scheduled_notifications
        where status = 'pending'
          and scheduled_for <= now()
        order by scheduled_for
        limit 50
        for update skip locked
    loop
        if rec.target_member_ids is null
           or array_length(rec.target_member_ids, 1) is null then
            -- إشعار عام — الإدراج وحده يشغّل التريغر الذي يتكفّل بالدفع
            insert into public.notifications (target_member_id, title, body, kind, created_by)
            values (null, rec.title, rec.body, rec.kind, rec.created_by);
        else
            foreach mid in array rec.target_member_ids loop
                insert into public.notifications (target_member_id, title, body, kind, created_by)
                values (mid, rec.title, rec.body, rec.kind, rec.created_by);
            end loop;
        end if;

        update public.scheduled_notifications
        set status = 'sent', sent_at = now()
        where id = rec.id;
    end loop;
end;
$function$;;
