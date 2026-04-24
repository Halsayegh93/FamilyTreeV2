-- إصلاح trigger منع ترقية الدور الذاتية
-- المشكلة: عندما عضو (role=member) يُعيد التسجيل، يريد التطبيق تغيير دوره إلى pending
-- لكن trigger "prevent_role_self_promotion" يُثبّت old.role → يبقى member → لا يظهر في قائمة الطلبات
--
-- الحل: نسمح بالتراجع فقط من member/active إلى pending خلال عملية إعادة التسجيل
-- التعريف: إعادة التسجيل = status يتغير إلى pending أو role يتغير إلى pending
-- نبقي منع الترقية (pending → member/admin/supervisor) مصاناً

create or replace function public.prevent_role_self_promotion()
returns trigger as $$
begin
  -- إذا المستخدم ليس مشرفاً (admin/supervisor/owner) فنطبق القواعد
  if public.current_user_role() not in ('admin', 'supervisor', 'owner') then

    -- السماح بالتراجع إلى pending فقط (إعادة تسجيل)
    -- المنطق: إذا الدور الجديد هو pending → هذه حالة إعادة تسجيل → اسمح بها
    if new.role = 'pending' and new.status = 'pending' then
      -- هذه عملية إعادة تسجيل مشروعة — اسمح بالتغيير
      return new;
    end if;

    -- منع أي تغيير آخر في الدور أو الحالة (حماية من الترقية الذاتية)
    new.role := old.role;
    new.status := old.status;

  end if;

  return new;
end;
$$ language plpgsql security definer;

-- إعادة ربط الـ trigger (تلقائي لأن الدالة تحديث in-place)
-- التأكد من أن الـ trigger موجود على الجدول
drop trigger if exists trg_prevent_role_self_promotion on public.profiles;
create trigger trg_prevent_role_self_promotion
  before update on public.profiles
  for each row
  execute function public.prevent_role_self_promotion();
