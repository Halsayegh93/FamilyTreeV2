do $do$
declare d text;
begin
  select pg_get_functiondef('public.notify_member_change()'::regprocedure) into d;
  execute replace(d, $x$values (admin_id, v_title, v_body, 'admin_edit', v_actor$x$, $x$values (admin_id, v_title, v_body, 'member_change', v_actor$x$);
end $do$;
update public.notifications set kind = 'member_change' where kind = 'admin_edit' and (details->>'v') = '2';
