do $do$
declare d text;
begin
  select pg_get_functiondef('public.notify_member_change()'::regprocedure) into d;
  execute replace(d, 'case when v_women or tg_op = ''DELETE'' then null else v_subject end', 'case when v_women then null else v_subject end');
  select pg_get_functiondef('public.merge_member_into_tree(uuid, uuid)'::regprocedure) into d;
  execute replace(d, 'birth_date         = coalesce(v_new.birth_date, v_tree.birth_date)', 'birth_date         = coalesce(v_tree.birth_date, v_new.birth_date)');
end $do$;

do $do$
declare d text;
begin
  select pg_get_functiondef('public.notify_member_change()'::regprocedure) into d;
  execute replace(d, E'\n  -- ربط طلب انضمام: نقل سجل، لا «حذف عضو» ولا «تعديل بيانات»\n  if current_setting(''family.merging'', true) = ''on'' then return null; end if;', '');
  select pg_get_functiondef('public.merge_member_into_tree(uuid, uuid)'::regprocedure) into d;
  execute replace(d, E'  perform set_config(''family.merging'', ''on'', true);\n\n', '');
end $do$;
