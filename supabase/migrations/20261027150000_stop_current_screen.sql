-- إيقاف تسجيل «الشاشة الحالية» (طلب المالك ٢٠٢٦-١٠-٢٧ «نعم وقف تسجيل الشاشة الحالية»):
-- update_my_current_screen يُبقي «آخر نشاط» فقط ويتجاهل الشاشة — يسري على كل النسخ القديمة بلا تحديث،
-- ويُمسح المحفوظ. التراجع: supabase/rollback/20261027150000_stop_current_screen_rollback.sql
create or replace function public.update_my_current_screen(p_screen text, p_source text default 'app'::text)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  -- الشاشة لا تُحفظ (p_screen / p_source يُتجاهلان) — آخر نشاط فقط
  update public.profiles
     set last_active_at = now()
   where id = auth.uid();
end;
$function$;

update public.profiles set current_screen = null, current_screen_source = null
 where current_screen is not null or current_screen_source is not null;
