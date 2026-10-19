-- طلب الانضمام هو مصدر الإشعار، لا إنشاء الملف المبدئي ولا إرسال التطبيق.
-- لا يحذف الإشعارات السابقة ولا يغيّر الأجهزة أو إرسال البريد.
begin;

drop trigger if exists trg_notify_admins_new_pending_member on public.profiles;

create unique index if not exists notifications_join_request_recipient_unique
on public.notifications (target_member_id, (details->>'join_request_id'))
where kind = 'link_request' and details->>'join_request_id' is not null;

create or replace function public.notify_admins_on_saved_join_request()
returns trigger language plpgsql security definer set search_path = public
as $function$
declare
  v_profile_id uuid;
  v_name text;
begin
  if new.status is distinct from 'pending'
     or new.request_type not in ('link_request', 'join_request') then
    return new;
  end if;
  v_profile_id := coalesce(new.requester_id, new.member_id);
  select coalesce(nullif(trim(full_name), ''), nullif(trim(first_name), ''), 'عضو جديد')
    into v_name from public.profiles where id = v_profile_id;
  if not found then return new; end if;

  insert into public.notifications
    (target_member_id, title, body, kind, created_by, is_read,
     request_id, request_type, subject_member_id, details)
  select p.id, 'طلب انضمام جديد', v_name || ' قدّم طلب انضمام جديد',
    'link_request', v_profile_id, false,
    v_profile_id, 'join_request', v_profile_id,
    jsonb_build_object('join_request_id', new.id)
  from public.profiles p
  where p.role in ('owner', 'admin', 'monitor', 'supervisor')
    and p.status = 'active' and p.id <> v_profile_id
  on conflict do nothing;
  return new;
end;
$function$;

drop trigger if exists trg_notify_admins_saved_join_request on public.admin_requests;
create trigger trg_notify_admins_saved_join_request
after insert on public.admin_requests for each row
execute function public.notify_admins_on_saved_join_request();

-- النسخ القديمة ما زالت تُدرج إشعاراً مشتركاً بعد حفظ الطلب؛ لا نفرّخه مرة ثانية.
create or replace function public.skip_client_join_notification()
returns trigger language plpgsql set search_path = public
as $function$
begin
  if new.target_member_id is null and new.kind = 'link_request'
     and new.request_type = 'join_request' then
    return null;
  end if;
  return new;
end;
$function$;
drop trigger if exists aa_skip_client_join_notification on public.notifications;
create trigger aa_skip_client_join_notification
before insert on public.notifications for each row
execute function public.skip_client_join_notification();

-- نحافظ على فتح الطلب وأزراره في الدفع بعد إزالة المسار المباشر.
create or replace function public.trigger_push_on_notification()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_secret text;
begin
  -- نسخ البثّ العام تُدرَج من داخل مُطلِق التفريخ (depth > 1): الدفع خرج
  -- مسبقاً مرة واحدة من الصف المشترك، فلا نكرّره آلاف المرات.
  if pg_trigger_depth() > 1
     and coalesce(new.kind, '') in ('admin_broadcast', 'app_update') then
    return new;
  end if;

  -- العضو أطفأ هذا النوع — يبقى الإشعار داخل التطبيق بلا push
  if not public.notification_push_allowed(new.target_member_id, coalesce(new.kind, ''), new.subject_member_id) then
    return new;
  end if;

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
        'kind', coalesce(new.kind, 'notification'),
        'request_id', new.request_id,
        'request_type', new.request_type,
        'notification_id', new.id
      )
    )
  );
  return new;
end;
$function$;

commit;
