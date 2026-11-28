-- تراجع 20261128190000_member_category_server_guards — يعيد الحي كما كان قبله:
-- يحذف الحارس على profiles، ويزيل سطر الحقن من دوال «عائلتي» الخمس عشرة، ثم يحذف الدالتين المساعدتين.
begin;

drop trigger if exists trg_profiles_category_guard on public.profiles;
drop function if exists public.trg_profiles_category_guard();

do $do$
declare
  fn  text;
  def text;
begin
  for fn in select p.proname from pg_proc p join pg_namespace s on s.oid = p.pronamespace
             where s.nspname = 'public' and p.prosrc like '%private.assert_my_family_allowed();   -- 20261128190000%' loop
    select pg_get_functiondef(p.oid) into def
      from pg_proc p join pg_namespace s on s.oid = p.pronamespace
     where s.nspname = 'public' and p.proname = fn;
    execute replace(def, E'\n  perform private.assert_my_family_allowed();   -- 20261128190000\n', E'\n');
  end loop;
end;
$do$;

drop function if exists private.assert_my_family_allowed();
drop function if exists private.category_locked(text);

commit;
