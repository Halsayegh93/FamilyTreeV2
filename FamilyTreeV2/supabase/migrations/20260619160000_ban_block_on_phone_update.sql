-- يمتد فحص الحظر ليشمل تغيير رقم العضو إلى رقم محظور (وليس الإنشاء فقط).
-- يُطلق فقط عند تغيّر phone_number — فلا يبطّئ بقية التعديلات.
drop trigger if exists trg_reject_banned_phone_registration on public.profiles;
create trigger trg_reject_banned_phone_registration
  before insert or update of phone_number on public.profiles
  for each row execute function public.reject_banned_phone_registration();
