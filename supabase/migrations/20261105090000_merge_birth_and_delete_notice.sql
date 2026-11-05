-- طلب المالك ٢٠٢٦-١١-٠٥: ربط طلب الانضمام
-- ١) notify_member_change بعد الحذف كان يكتب subject_member_id لسجل محذوف، فيفشل الحذف والدمج (FK) منذ ٢٠٢٦-١٠-٣١.
-- ٢) merge_member_into_tree: تاريخ ميلاد طالب الانضمام يسبق تاريخ الشجرة (في الشجرة تواريخ وهمية 2026-01-26).
do $do$
declare
  d text;
  a text := 'case when v_women then null else v_subject end';
  b text := 'birth_date         = coalesce(v_tree.birth_date, v_new.birth_date)';
begin
  select pg_get_functiondef('public.notify_member_change()'::regprocedure) into d;
  if position(a in d) = 0 then raise exception 'notify_member_change: expected text not found'; end if;
  execute replace(d, a, 'case when v_women or tg_op = ''DELETE'' then null else v_subject end');
  select pg_get_functiondef('public.merge_member_into_tree(uuid, uuid)'::regprocedure) into d;
  if position(b in d) = 0 then raise exception 'merge_member_into_tree: expected text not found'; end if;
  execute replace(d, b, 'birth_date         = coalesce(v_new.birth_date, v_tree.birth_date)');
end $do$;

-- ٣) الربط ينقل سجلاً: لا إشعار «حذف عضو» ولا «تعديل بيانات» للإدارة.
do $do$
declare
  d text;
  a text := 'if pg_trigger_depth() > 1 then return null; end if;';
  b text := '  -- ─── 1) تحديث السجل الجديد ببيانات الشجرة';
begin
  select pg_get_functiondef('public.notify_member_change()'::regprocedure) into d;
  if position(a in d) = 0 then raise exception 'notify: expected text not found'; end if;
  execute replace(d, a, a || E'\n  -- ربط طلب انضمام: نقل سجل، لا «حذف عضو» ولا «تعديل بيانات»\n  if current_setting(''family.merging'', true) = ''on'' then return null; end if;');
  select pg_get_functiondef('public.merge_member_into_tree(uuid, uuid)'::regprocedure) into d;
  if position(b in d) = 0 then raise exception 'merge: expected text not found'; end if;
  execute replace(d, b, E'  perform set_config(''family.merging'', ''on'', true);\n\n' || b);
end $do$;
