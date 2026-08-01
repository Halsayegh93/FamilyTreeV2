-- مُستخرَجة من سجل الإنتاج (supabase_migrations.schema_migrations)
-- كانت مطبَّقة على القاعدة لكن ملفها مفقود من المستودع.

-- عيب: علامة التفريخ كُتبت داخل عمود details الذي يتوقّع شكلاً محدّداً
-- ({v, changes})، فصار فكّ ترميزه يفشل في التطبيق وتسقط قائمة الإشعارات
-- بأكملها (الإشعارات والمستجدات وسجل النشاط تظهر فارغة).
-- الحل: لا نلمس details إطلاقاً — نكتم الدفع عبر عمق المُطلِق بدل العلامة.

-- 1) تنظيف الصفوف التي كُتبت بالعلامة
update public.notifications
set details = null
where details ? '_fanout';

-- 2) كتم الدفع لنسخ البثّ العام عبر pg_trigger_depth (بلا لمس details)
create or replace function public.trigger_push_on_notification()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_secret text;
begin
  -- نسخ البثّ العام تُدرَج من داخل مُطلِق التفريخ (depth > 1): الدفع خرج
  -- مسبقاً مرة واحدة من الصف المشترك، فلا نكرّره آلاف المرات.
  if pg_trigger_depth() > 1
     and coalesce(new.kind, '') in ('admin_broadcast', 'app_update') then
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
$$;

-- 3) التفريخ بلا أي علامة في details
create or replace function public.fanout_broadcast_notification()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if new.target_member_id is not null then
    return new;
  end if;

  if coalesce(new.kind, '') in ('admin_broadcast', 'app_update') then
    insert into public.notifications
      (target_member_id, title, body, kind, created_by, created_at, is_read,
       request_id, request_type, details)
    select p.id, new.title, new.body, new.kind, new.created_by,
           coalesce(new.created_at, timezone('utc', now())), false,
           new.request_id, new.request_type, new.details
    from public.profiles p
    where coalesce(p.role, '') <> 'pending';
    return new;   -- الصف المشترك يبقى ليخرج الدفع مرة واحدة
  end if;

  insert into public.notifications
    (target_member_id, title, body, kind, created_by, created_at, is_read,
     request_id, request_type, details)
  select p.id, new.title, new.body, new.kind, new.created_by,
         coalesce(new.created_at, timezone('utc', now())), false,
         new.request_id, new.request_type, new.details
  from public.profiles p
  where p.role in ('owner', 'admin', 'monitor', 'supervisor');
  return null;
end;
$$;;
