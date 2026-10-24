-- تراجع 20261021110000_app_config: يحذف الجدولين (والقيم وسجلها) والدوال العامة والداخلية. لم يتغيّر شيء قائم في الترحيل،
-- فلا شيء يُعاد. يعمل أيضاً على قاعدة لم يُطبَّق عليها الترحيل (كل حذف مشروط).
-- الترتيب: تراجع أولاً عن كل ترحيل بعده يقرأ config_* (20261021120000، 20261021140000، 20261021150000) — وإلا ترفض
-- هذه الخطوة (الحارس أدناه)، لأن دالة سيرفر تنادي config_int بعد حذفها تتعطل (إعلان الوفاة، المهل، رسائل الدخول…).

do $$
declare v_fns text;
begin
  select string_agg(n.nspname || '.' || p.proname, ', ' order by p.proname) into v_fns
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'private')
     and p.prosrc ~ 'public\.config_(int|text|bool|json)\('
     and p.proname not in ('config_int', 'config_text', 'config_bool', 'config_json');
  if v_fns is not null then
    raise exception 'تراجع app_config مرفوض: دوال ما زالت تقرأ config_* (%) — تراجع عن ترحيلاتها أولاً', v_fns;
  end if;
end $$;

drop function if exists public.set_app_config(text, jsonb);
drop function if exists public.app_config_public();
drop function if exists public.app_config();
drop function if exists public.config_int(text, integer);
drop function if exists public.config_text(text, text);
drop function if exists public.config_bool(text, boolean);
drop function if exists public.config_json(text, jsonb);
drop table if exists public.app_config_history;
drop table if exists public.app_config;
drop function if exists private.app_config_log();
drop function if exists private.app_config_guard();
drop function if exists private.app_config_problem(text, jsonb, numeric, numeric, integer, jsonb);
drop function if exists private.app_config_text_problem(text, boolean, integer, jsonb);
