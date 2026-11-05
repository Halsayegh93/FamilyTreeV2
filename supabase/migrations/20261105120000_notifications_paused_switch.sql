-- طلب المالك ٢٠٢٦-١١-٠٥: زر يوقف إشعارات الجوال عن التطبيق كله، منفصل عن وضع الصيانة. الإشعار يبقى داخل التطبيق.
alter table public.app_settings add column if not exists notifications_paused boolean not null default false;

do $do$
declare d text; a text;
begin
  select pg_get_functiondef('public.trigger_push_on_notification()'::regprocedure) into d;
  a := $x$  -- إضافة ابن عادية: داخل التطبيق فقط، والجوال لـ«راجعه»$x$;
  if position(a in d) = 0 then raise exception 'push: expected text not found'; end if;
  execute replace(d, a, $x$  -- زر إيقاف الإشعارات
  if coalesce((select s.notifications_paused from public.app_settings s limit 1), false) then
    return new;
  end if;

$x$ || a);

  select pg_get_functiondef('public.reserve_delivery_attempt(text,text,text,integer,integer)'::regprocedure) into d;
  a := $x$  perform pg_advisory_xact_lock(hashtextextended(p_scope||':'||p_actor,0));$x$;
  if position(a in d) = 0 then raise exception 'reserve: expected text not found'; end if;
  execute replace(d, a, $x$  -- زر إيقاف الإشعارات: push-admins يرجع بلا إرسال
  if p_scope = 'push-admins' and coalesce((select s.notifications_paused from public.app_settings s limit 1), false) then
    return 'duplicate';
  end if;
$x$ || a);
end $do$;
