-- إضافة ابن للعائلة عبر السيرفر مع توجيه حسب الجنس:
--  أنثى → women_members فقط (لا تدخل الشجرة العامة).
--  ذكر  → profiles (الشجرة العامة) ثم ينعكس تلقائياً لشجرة النساء.
-- مسموح: الإدارة، أو المستخدم يضيف لعقدته نفسها (p_parent_id = auth.uid()).
create or replace function public.add_family_child(
  p_parent_id uuid,
  p_name text,
  p_gender text default 'male',
  p_birth date default null,
  p_deceased boolean default false,
  p_death date default null,
  p_sort integer default 0,
  p_parent_full_name text default ''
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  g text := lower(coalesce(p_gender, 'male'));
  new_id uuid := gen_random_uuid();
  nm text := trim(coalesce(p_name, ''));
  chained text := case
    when coalesce(trim(p_parent_full_name), '') = '' then nm
    else nm || ' ' || trim(p_parent_full_name)
  end;
begin
  if not (public.is_moderator() or p_parent_id = auth.uid()) then
    raise exception 'not_authorized';
  end if;
  if nm = '' then
    raise exception 'name_required';
  end if;

  if g = 'female' then
    insert into public.women_members(
      id, first_name, full_name, parent_id, gender,
      is_deceased, birth_date, death_date, sort_order)
    values (
      new_id, nm, chained, p_parent_id, 'female',
      coalesce(p_deceased, false), p_birth,
      case when p_deceased then p_death else null end,
      coalesce(p_sort, 0));
  else
    insert into public.profiles(
      id, first_name, full_name, father_id, gender, status, role,
      is_deceased, birth_date, death_date, sort_order,
      is_phone_verified, is_hr_member)
    values (
      new_id, nm, chained, p_parent_id, 'male', 'active', 'member',
      coalesce(p_deceased, false), p_birth,
      case when p_deceased then p_death else null end,
      coalesce(p_sort, 0), false, false);
    -- إدراج profiles يُنشئ نسخة ذكر في شجرة النساء (نفس id) عبر المزامنة.
  end if;
  return new_id;
end;
$$;

grant execute on function public.add_family_child(uuid, text, text, date, boolean, date, integer, text) to authenticated;;
