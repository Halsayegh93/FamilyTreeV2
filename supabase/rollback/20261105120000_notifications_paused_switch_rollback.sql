do $do$
declare d text; s int; e int;
begin
  select pg_get_functiondef('public.trigger_push_on_notification()'::regprocedure) into d;
  s := position($x$  -- زر إيقاف الإشعارات$x$ in d);
  e := position($x$  -- إضافة ابن عادية$x$ in d);
  execute overlay(d placing '' from s for e - s);
  select pg_get_functiondef('public.reserve_delivery_attempt(text,text,text,integer,integer)'::regprocedure) into d;
  s := position($x$  -- زر إيقاف الإشعارات$x$ in d);
  e := position($x$  perform pg_advisory_xact_lock$x$ in d);
  execute overlay(d placing '' from s for e - s);
end $do$;
alter table public.app_settings drop column if exists notifications_paused;
