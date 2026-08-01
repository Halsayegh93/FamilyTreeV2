-- مُستخرَجة من سجل الإنتاج (supabase_migrations.schema_migrations)
-- كانت مطبَّقة على القاعدة لكن ملفها مفقود من المستودع.

-- إصلاح: بعد أن صار التطبيق يقرأ صفوف العضو فقط، صارت رسائل البثّ العام
-- (صف واحد بـ target_member_id = NULL) غير مرئية داخل التطبيق — يصل الدفع
-- ولا يظهر الإشعار في المركز. الحل: تفريخ نسخة مستقلة لكل عضو (تحكّم فردي)
-- مع إبقاء الصف المشترك ليُطلق الدفع مرة واحدة بدل آلاف المرات.

-- 1) مُطلق الدفع يتجاهل نسخ التفريخ (الدفع يخرج من الصف المشترك فقط)
create or replace function public.trigger_push_on_notification()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_secret text;
begin
  if coalesce(new.details->>'_fanout', '') = '1' then
    return new;   -- نسخة تفريخ: الدفع خرج مسبقاً من الصف المشترك
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

-- 2) التفريخ: بثّ عام → كل الأعضاء · تنبيه إدارة → فريق الإدارة
create or replace function public.fanout_broadcast_notification()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if new.target_member_id is not null then
    return new;   -- إشعار شخصي: يمرّ كما هو
  end if;

  if coalesce(new.kind, '') in ('admin_broadcast', 'app_update') then
    -- بثّ عام لكل الأعضاء: نسخة مستقلة لكل عضو ليتحكّم بها (قراءة/حذف)
    insert into public.notifications
      (target_member_id, title, body, kind, created_by, created_at, is_read,
       request_id, request_type, details)
    select p.id, new.title, new.body, new.kind, new.created_by,
           coalesce(new.created_at, timezone('utc', now())), false,
           new.request_id, new.request_type,
           coalesce(new.details, '{}'::jsonb) || jsonb_build_object('_fanout', '1')
    from public.profiles p
    where coalesce(p.role, '') <> 'pending';
    return new;   -- يبقى الصف المشترك ليُطلق الدفع مرة واحدة للجميع
  end if;

  -- تنبيهات فريق الإدارة: نسخة لكل عضو إدارة (بلا علامة تفريخ ليصله الدفع)
  insert into public.notifications
    (target_member_id, title, body, kind, created_by, created_at, is_read,
     request_id, request_type, details)
  select p.id, new.title, new.body, new.kind, new.created_by,
         coalesce(new.created_at, timezone('utc', now())), false,
         new.request_id, new.request_type, new.details
  from public.profiles p
  where p.role in ('owner', 'admin', 'monitor', 'supervisor');
  return null;   -- لا يُدرج الصف المشترك
end;
$$;;
