-- تراجع 20261027150000_stop_current_screen — يعيد حفظ الشاشة (القيم الممسوحة لا تعود)
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

  update public.profiles
     set current_screen = p_screen,
         current_screen_source = p_source,
         last_active_at = now()
   where id = auth.uid();
end;
$function$;
