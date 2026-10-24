-- تراجع 20261015170000: يعيد الحارس كما كان حياً قبله (الشرطان في عبارة واحدة)
create or replace function public.trg_profiles_protect_delete()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
begin
  if old.role = 'owner' and session_user not in ('postgres', 'supabase_admin') then
    raise exception 'owner_protected'
      using hint = 'لا يمكن حذف المالك';
  end if;
  if session_user = 'supabase_auth_admin'
     and exists (select 1 from auth.users u where u.id = old.id) then
    raise exception 'account_protected'
      using hint = 'ملف عضو مربوط بحساب دخول لا يُحذف آلياً';
  end if;
  if auth.uid() is not null then
    if old.id = auth.uid() then
      raise exception 'cannot_delete_self'
        using hint = 'لا يمكن حذف سجلك من لوحة الإدارة';
    end if;
  end if;
  return old;
end;
$function$;
