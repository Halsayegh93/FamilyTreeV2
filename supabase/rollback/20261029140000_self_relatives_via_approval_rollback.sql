-- تراجع 20261029140000_self_relatives_via_approval: الدوال الأصلية ترجع لمكانها بنصّها (نُقلت ولم تُعدَّل)،
-- والحارس وأسماء الأنواع يرجعان بعكس التعديل النصّي نفسه. طلبات relative_add المعلّقة تبقى صفوفاً بلا تنفيذ — راجعها/احذفها أولاً.
begin;
drop function public.decide_admin_request(uuid, text, text, jsonb);
alter function private.decide_admin_request_core(uuid, text, text, jsonb) rename to decide_admin_request;
alter function private.decide_admin_request(uuid, text, text, jsonb) set schema public;
grant execute on function public.decide_admin_request(uuid, text, text, jsonb) to authenticated, service_role;

drop function public.add_self_wife(text, boolean);
drop function public.add_self_mother(text);
drop function public.add_or_link_self_relative(text, uuid, uuid, text);
alter function private.add_self_wife_direct(text, boolean) rename to add_self_wife;
alter function private.add_self_wife(text, boolean) set schema public;
alter function private.add_self_mother_direct(text) rename to add_self_mother;
alter function private.add_self_mother(text) set schema public;
alter function private.add_or_link_self_relative_direct(text, uuid, uuid, text) rename to add_or_link_self_relative;
alter function private.add_or_link_self_relative(text, uuid, uuid, text) set schema public;
-- الصلاحيات السابقة حرفياً
grant execute on function public.add_self_wife(text, boolean) to authenticated, service_role;
grant execute on function public.add_self_mother(text) to public, anon, authenticated, service_role;
grant execute on function public.add_or_link_self_relative(text, uuid, uuid, text) to authenticated, service_role;

drop function if exists private.self_relative_request(text, jsonb, text, text);
drop function if exists private.self_relative_needs_request();

do $mig$
declare d text := pg_get_functiondef('public.guard_admin_request_insert()'::regprocedure); n text;
begin
  n := replace(d, $x$'phone_change','child_add','news_report','content_report','account_delete','privacy_request','relative_add') then$x$,
                  $x$'phone_change','child_add','news_report','content_report','account_delete','privacy_request') then$x$);
  n := replace(n, E'  -- «إضافة قريبة» تُنشئها add_self_wife/add_self_mother/add_or_link_self_relative فقط (20261029140000)\n'
               || E'  if new.request_type = ''relative_add'' and coalesce(current_setting(''app.self_relative_rpc'', true), '''') <> ''on'' then\n'
               || E'    raise exception ''admin_request_type_not_allowed'' using errcode = ''42501'';\n'
               || E'  end if;\n', '');
  execute n;
  -- md5(pg_get_functiondef) قبل الترحيل = c86122a8761258fb60009f3faaefb565
end $mig$;

do $mig$
declare d text := pg_get_functiondef('public.admin_request_label(text)'::regprocedure);
begin
  execute replace(d, $x$
    when 'relative_add'     then 'طلب إضافة قريبة'
    when 'account_delete'   then 'طلب حذف الحساب'$x$, '');
end $mig$;

delete from public.app_config where key = 'self_relative_requires_approval';
commit;
