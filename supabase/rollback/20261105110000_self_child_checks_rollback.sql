-- يرجع الدوال الثلاث إلى ما قبل 20261105110000 (نُسخت قبل التطبيق في scratchpad الجلسة؛ هنا إزالة بالاستبدال).
delete from public.app_config where key = 'photo_reminder_days';
do $do$
declare d text; s int; e int;
begin
  select pg_get_functiondef('public.add_family_child(uuid,text,text,date,boolean,date,integer,text)'::regprocedure) into d;
  s := position($x$if p_birth is not null and p_birth > (now()$x$ in d);
  e := position($x$perform set_config('family.self_child', 'on', true);$x$ in d);
  execute overlay(d placing '' from s for e - s);
  select pg_get_functiondef('public.notify_member_change()'::regprocedure) into d;
  s := position($x$  -- العضو أضاف ابنه بنفسه$x$ in d);
  e := position($x$  for admin_id in$x$ in d);
  execute overlay(d placing '' from s for e - s);
  select pg_get_functiondef('public.trigger_push_on_notification()'::regprocedure) into d;
  s := position($x$-- إضافة ابن عادية$x$ in d);
  e := position($x$-- العضو أطفأ هذا النوع$x$ in d);
  execute overlay(d placing '' from s for e - s);
end $do$;
