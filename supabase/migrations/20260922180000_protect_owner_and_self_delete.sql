-- حماية من الحذف النهائي (فحص الثغرات 2026-09-22)
--
-- سياسة الحذف كانت تسمح لأي مدير بحذف أي صف في profiles — بما فيها المالك
-- ونفسه. هذا الحارس يرفض من داخل التطبيق:
--   • حذف المالك
--   • حذف المستخدم لسجله بنفسه من لوحة الإدارة
-- حذف الحساب الذاتي (delete-account) يعمل بمفتاح الخدمة (auth.uid() = null)
-- فلا يتأثر. الأبناء: father_id يُفرَّغ تلقائياً (ON DELETE SET NULL).

create or replace function public.trg_profiles_protect_delete()
returns trigger
language plpgsql
as $$
begin
  if auth.uid() is not null then
    if old.role = 'owner' then
      raise exception 'owner_protected'
        using hint = 'لا يمكن حذف المالك';
    end if;
    if old.id = auth.uid() then
      raise exception 'cannot_delete_self'
        using hint = 'لا يمكن حذف سجلك من لوحة الإدارة';
    end if;
  end if;
  return old;
end;
$$;

drop trigger if exists trg_profiles_protect_delete on public.profiles;
create trigger trg_profiles_protect_delete
  before delete on public.profiles
  for each row execute function public.trg_profiles_protect_delete();
