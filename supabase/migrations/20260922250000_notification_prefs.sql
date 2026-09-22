-- أنواع الإشعارات تشتغل فعلاً (طلب المالك)
--
-- كانت مفاتيح «التعليقات/الإعجابات/…» تُحفظ في الجوال فقط ولا يقرأها شيء، فيصل
-- كل شيء. الحين: اختيار العضو في profiles.notification_prefs، ومُطلِق الدفع
-- لا يرسل push للنوع المطفأ (الإشعار يبقى داخل التطبيق).
--   مفاتيح: likes, comments, news, profile, requests, admin_activity — false = مطفأ
--   إعلانات الإدارة وتحديثات التطبيق والتجربة تصل دائماً.

alter table public.profiles
  add column if not exists notification_prefs jsonb not null default '{}'::jsonb;

create or replace function public.notification_category(p_kind text, p_target uuid, p_subject uuid)
returns text
language sql
immutable
as $$
  select case
    when p_kind in ('admin_broadcast', 'app_update', 'test') then null
    when p_kind = 'news_like' then 'likes'
    when p_kind = 'news_comment' then 'comments'
    when p_kind = 'news_published' then 'news'
    when p_kind like 'admin_edit%' and p_subject is not null and p_subject = p_target then 'profile'
    when p_kind in ('join_approved', 'account_activated', 'role_change', 'request_rejected')
      or p_kind like '%\_approved' or p_kind like '%\_rejected' then 'requests'
    else 'admin_activity'
  end;
$$;

create or replace function public.notification_push_allowed(p_target uuid, p_kind text, p_subject uuid)
returns boolean
language sql
stable security definer
set search_path to 'public'
as $$
  select case
    when p_target is null then true
    when public.notification_category(p_kind, p_target, p_subject) is null then true
    else coalesce(
      (select (notification_prefs ->> public.notification_category(p_kind, p_target, p_subject)) is distinct from 'false'
       from public.profiles where id = p_target),
      true)
  end;
$$;

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
        'kind', coalesce(new.kind, 'notification')
      )
    )
  );
  return new;
end;
$function$;
