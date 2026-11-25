-- تراجع 20261125120000_push_image: مشغّل الدفع والموزّع يرجعان حرفياً كما كانا، ثم يُحذف عمود details من المجدولة.
-- الصور المرفوعة في news/push/ تبقى (لا تُحذف من التراجع).

do $do$
declare d text; a text;
begin
  select pg_get_functiondef('public.trigger_push_on_notification()'::regprocedure) into d;
  a := $x$ || case
        -- صورة الإشعار: مسار رفع الإدارة فقط (push/<uuid>.jpg) — بلا صورة لا يُضاف شيء
        when coalesce(new.details ->> 'image_path', '') ~ '^push/[0-9a-f-]{36}\.(jpg|jpeg|png)$'
          then jsonb_build_object('image_path', new.details ->> 'image_path')
        else '{}'::jsonb
      end$x$;
  if position(a in d) = 0 then
    raise notice 'push: image_path patch not found — nothing to undo';
  else
    execute replace(d, a, '');
  end if;
end $do$;

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
$function$;

alter table public.scheduled_notifications drop column if exists details;
