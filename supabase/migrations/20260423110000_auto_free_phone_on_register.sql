-- Trigger يُعالج تعارض الرقم تلقائياً قبل إدراج profile جديد
-- عندما مستخدم يُعيد التسجيل وله عضو في الشجرة بنفس الرقم →
-- يُحرر الرقم من العضو القديم ويُكمل التسجيل بدون أي تعديل على Swift

create or replace function public.trg_profiles_free_conflicting_phone()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_conflicting_id uuid;
begin
  -- تجاهل إذا الرقم فارغ
  if new.phone_number is null or trim(new.phone_number) = '' then
    return new;
  end if;

  -- البحث عن عضو آخر (غير هذا السجل) عنده نفس الرقم
  select id into v_conflicting_id
  from public.profiles
  where phone_number = new.phone_number
    and id <> new.id
  limit 1;

  if v_conflicting_id is not null then
    -- حرر الرقم من العضو القديم حتى يمر الـ unique constraint
    update public.profiles
      set phone_number = null
      where id = v_conflicting_id;

    raise notice '[REGISTER] حُرر الرقم % من العضو % للسماح بإعادة التسجيل',
      new.phone_number, v_conflicting_id;
  end if;

  return new;
end;
$$;

-- ربط الـ trigger بجدول profiles — يعمل قبل كل INSERT
drop trigger if exists profiles_free_conflicting_phone on public.profiles;
create trigger profiles_free_conflicting_phone
  before insert on public.profiles
  for each row
  execute function public.trg_profiles_free_conflicting_phone();
