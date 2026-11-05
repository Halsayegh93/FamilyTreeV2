-- طلب المالك ٢٠٢٦-١١-٠٥ «افصل الإشعارات بين الإدارة ومركز الإشعارات»: نسخة 49 لا تعرف member_change فتعرضه في المركز العام.
-- admin_edit تعرفه كل النسخ كـ«نشاط الفريق» في صفحة الإدارة؛ النسخ الأحدث ترجعه member_change عند القراءة (details.v = 2).
do $do$
declare d text;
begin
  select pg_get_functiondef('public.notify_member_change()'::regprocedure) into d;
  if position($x$values (admin_id, v_title, v_body, 'member_change', v_actor$x$ in d) = 0 then
    raise exception 'notify: expected text not found';
  end if;
  execute replace(d, $x$values (admin_id, v_title, v_body, 'member_change', v_actor$x$, $x$values (admin_id, v_title, v_body, 'admin_edit', v_actor$x$);
end $do$;
update public.notifications set kind = 'admin_edit' where kind = 'member_change';
