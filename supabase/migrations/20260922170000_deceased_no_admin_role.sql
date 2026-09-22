-- المتوفى لا يحمل دوراً إدارياً (طلب المالك)
--
-- التطبيقان يخفيان المتوفين من «فريق الإدارة» ومن اختيار العضو عند التعيين،
-- وهذا الحارس يضمن نفس القاعدة من السيرفر:
--   ١. تسجيل عضو متوفى وهو مدير/مراقب/مشرف → يرجع دوره «عضو» تلقائياً
--      (بدل أن يبقى مسؤولاً مخفياً لا يظهر في الشاشة).
--   ٢. تعيين دور إداري لعضو متوفى → يُرفض برسالة deceased_cannot_hold_role.
-- المالك مستثنى — دوره ثابت ولا يُمسّ.

create or replace function public.trg_profiles_deceased_no_admin_role()
returns trigger
language plpgsql
as $$
begin
  if coalesce(new.is_deceased, false)
     and new.role in ('admin', 'monitor', 'supervisor') then
    if tg_op = 'UPDATE'
       and new.role is not distinct from old.role then
      -- الدور ما تغيّر — العضو صار متوفى (أو تعديل آخر عليه): نرجعه عضواً
      new.role := 'member';
    else
      raise exception 'deceased_cannot_hold_role'
        using hint = 'لا يمكن تعيين دور إداري لعضو متوفى';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_zz_deceased_no_admin_role on public.profiles;
create trigger trg_zz_deceased_no_admin_role
  before insert or update of is_deceased, role on public.profiles
  for each row execute function public.trg_profiles_deceased_no_admin_role();
