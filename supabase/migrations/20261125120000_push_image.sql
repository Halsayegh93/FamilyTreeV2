-- «صورة الإشعار» (موافقة المالك ٢٠٢٦-١١-٢٥، الخيار ب «زر صورة خاص بالإشعار»): صورة اختيارية في «إنشاء ← إعلان»
-- تظهر داخل إشعار الجوال (شاشة القفل والشريط). الآيفون يرفعها إلى `news/push/<uuid>.jpg` (رفع الإدارة في مستودع
-- الأخبار مسموح أصلاً بـ`news_insert_admin`) ويحفظ مسارها في `details.image_path`.
--  ١) `scheduled_notifications.details` — الإشعار المجدول يحمل الصورة لموعده.
--  ٢) `dispatch_due_scheduled_notifications` ينسخ `details` لصفوف `notifications` (و`fanout_broadcast_notification`
--     ينسخ `details` أصلاً لنسخ الأعضاء).
--  ٣) `trigger_push_on_notification` يضيف `image_path` لما يرسله لـ`push-on-notification` — فقط حين يكون المسار
--     بشكل `push/<uuid>.jpg|jpeg|png`؛ بلا صورة يبقى المُرسَل كما كان حرفياً (لا مفتاح `image_path` أصلاً).
--     الدالة الطرفية توقّع رابطاً (المستودع خاص) وتضع `mutable-content` و`image_url`، وامتداد الآيفون يرفقها.
-- الترقيع بالاستبدال النصّي على التعريف الحيّ كما في 20261105110000 و20261105120000.
-- التراجع: supabase/rollback/20261125120000_push_image_rollback.sql

alter table public.scheduled_notifications add column if not exists details jsonb;

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
            -- details (صورة الإشعار) تنتقل كما هي؛ null = كما كان قبل الصورة
            insert into public.notifications (target_member_id, title, body, kind, created_by, details)
            values (null, rec.title, rec.body, rec.kind, rec.created_by, rec.details);
        else
            foreach mid in array rec.target_member_ids loop
                insert into public.notifications (target_member_id, title, body, kind, created_by, details)
                values (mid, rec.title, rec.body, rec.kind, rec.created_by, rec.details);
            end loop;
        end if;

        update public.scheduled_notifications
        set status = 'sent', sent_at = now()
        where id = rec.id;
    end loop;
end;
$function$;

do $do$
declare d text; a text;
begin
  select pg_get_functiondef('public.trigger_push_on_notification()'::regprocedure) into d;
  if position('image_path' in d) > 0 then
    raise notice 'push: image_path already present — skipped';
    return;
  end if;
  a := $x$        'notification_id', new.id
      )$x$;
  if position(a in d) = 0 then raise exception 'push: expected text not found'; end if;
  execute replace(d, a, a || $x$ || case
        -- صورة الإشعار: مسار رفع الإدارة فقط (push/<uuid>.jpg) — بلا صورة لا يُضاف شيء
        when coalesce(new.details ->> 'image_path', '') ~ '^push/[0-9a-f-]{36}\.(jpg|jpeg|png)$'
          then jsonb_build_object('image_path', new.details ->> 'image_path')
        else '{}'::jsonb
      end$x$);
end $do$;
