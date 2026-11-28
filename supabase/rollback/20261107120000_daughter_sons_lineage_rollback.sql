-- تراجع 20261107120000_daughter_sons_lineage. العقد التي أُنشئت (أزواج من خارج العائلة وأبناؤهم) تبقى في
-- women_members كما هي (حماية روابط العائلة) — يضيع علم is_outside_family فقط فيظهر الزوج جذراً في التطبيق.
-- طلبات lineage_request المعلّقة تبقى صفوفاً بلا تنفيذ — راجعها/احذفها أولاً.
begin;
drop function if exists public.add_outside_husband(uuid, text, boolean);
drop function if exists public.decide_lineage_request(uuid, text, text);
drop function if exists public.submit_daughter_son_lineage(uuid, uuid, text, text, text, text, boolean);
drop function if exists public.my_lineage_status();
drop function if exists public.approve_join_as_daughter_son(uuid);

do $mig$
declare d text := pg_get_functiondef('public.guard_admin_request_insert()'::regprocedure); n text;
begin
  n := replace(d, $x$'account_delete','privacy_request','relative_add','lineage_request') then$x$,
                  $x$'account_delete','privacy_request','relative_add') then$x$);
  n := replace(n, E'  -- «طلب النسب» تُنشئه submit_daughter_son_lineage فقط (20261107120000)\n'
               || E'  if new.request_type = ''lineage_request'' and coalesce(current_setting(''app.lineage_rpc'', true), '''') <> ''on'' then\n'
               || E'    raise exception ''admin_request_type_not_allowed'' using errcode = ''42501'';\n'
               || E'  end if;\n', '');
  execute n;
end $mig$;

do $mig$
declare d text := pg_get_functiondef('public.admin_request_label(text)'::regprocedure);
begin
  execute replace(d, E'\n    when ''lineage_request''  then ''طلب النسب''', '');
end $mig$;

create or replace function public.workflow_specialist_role(p_type text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case
    when p_type in ('news_report', 'content_report') then 'supervisor'
    when p_type = 'contact_message' then null
    else 'monitor'
  end;
$function$;

delete from public.app_config where key in ('daughter_sons_enabled', 'daughter_sons_max_resubmits',
  'daughter_sons_require_grandfather', 'daughter_sons_allow_later', 'daughter_sons_texts');
drop table if exists public.daughter_son_lineage;
alter table public.women_members drop column if exists is_outside_family;
commit;
