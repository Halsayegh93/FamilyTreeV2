-- إصلاح «حذف نهائي» من التطبيق (طلب المالك ٢٠٢٦-١٠-١٥ «علي حذفته… للحين ما انحذف»)
--
-- منذ 20261001100000 كان شرط الحارس يقرأ auth.users في نفس العبارة:
--   if session_user = 'supabase_auth_admin' and exists (select 1 from auth.users …)
-- وPostgres يفحص صلاحية كل جدول في العبارة عند بدء التنفيذ ولو لم يُقيَّم شقّها، فكل حذف من التطبيق
-- (المالك/المدير، دور authenticated) يفشل بـ «permission denied for table users» (403) — سجل السيرفر ١٥:٢٠:٤٤.
-- الإصلاح: الشرط الداخلي في if منفصل فلا يُجهَّز ولا يُفحص إلا لجلسة supabase_auth_admin. السلوك نفسه حرفياً.
-- التراجع: supabase/rollback/20261015170000_profiles_delete_guard_fix_rollback.sql

create or replace function public.trg_profiles_protect_delete()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
begin
  -- المالك: لا حذف من التطبيق ولا من أي آلية — يدوياً من لوحة التحكم فقط
  if old.role = 'owner' and session_user not in ('postgres', 'supabase_admin') then
    raise exception 'owner_protected'
      using hint = 'لا يمكن حذف المالك';
  end if;
  -- أي عضو له حساب دخول: لا يُحذف ملفه من مسارات الدخول الآلية (ربط/إنشاء حساب).
  -- منفصل عن شرط الجلسة: جلسات التطبيق لا تملك قراءة auth.users فلا تُجهَّز العبارة لها أصلاً.
  if session_user = 'supabase_auth_admin' then
    if exists (select 1 from auth.users u where u.id = old.id) then
      raise exception 'account_protected'
        using hint = 'ملف عضو مربوط بحساب دخول لا يُحذف آلياً';
    end if;
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
