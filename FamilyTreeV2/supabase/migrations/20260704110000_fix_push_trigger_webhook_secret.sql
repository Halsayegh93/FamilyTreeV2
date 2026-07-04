-- إصلاح: البوش الخارجي متوقف — إدراج أي إشعار كان يستدعي push-on-notification
-- ويرجع 401 Unauthorized (مثبت من net._http_response).
--
-- سببان:
-- 1) trigger_push_on_notification أُعيد إنشاؤه من الداشبورد بنسخة قديمة ترسل
--    anon key فقط بدون ترويسة x-webhook-secret التي صارت الدالة تشترطها
--    منذ تحصين 20260619100000 (لم يكن التريغر في أي migration أصلاً).
-- 2) قيمة private.app_secrets.push_webhook_secret لم تعد تطابق سرّ الدالة
--    PUSH_WEBHOOK_SECRET — تُزامَن خارج هذا الملف (لا نضع أسراراً في الريبو):
--    update private.app_secrets set value = '<PUSH_WEBHOOK_SECRET>' where key = 'push_webhook_secret';
--
-- هنا نعيد تعريف التريغر ليقرأ السرّ من private.app_secrets (security definer)
-- ويرسله كترويسة x-webhook-secret — نفس نمط dispatch_due_scheduled_notifications.

create or replace function public.trigger_push_on_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_secret text;
begin
  select value into v_secret from private.app_secrets where key = 'push_webhook_secret';
  perform net.http_post(
    url := 'https://poxyxsgvzwmnmewytsiw.supabase.co/functions/v1/push-on-notification'::text,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', coalesce(v_secret, '')
    ),
    body := jsonb_build_object(
      'record', jsonb_build_object(
        'target_member_id', new.target_member_id,
        'title', new.title,
        'body', new.body,
        'kind', coalesce(new.kind, 'notification')
      )
    )
  );
  return new;
end;
$$;

drop trigger if exists trg_push_on_notification on public.notifications;
create trigger trg_push_on_notification
  after insert on public.notifications
  for each row
  execute function public.trigger_push_on_notification();
