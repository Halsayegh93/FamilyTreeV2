-- نقل ابن بين الشجرتين حسب الجنس (إدارة فقط):
--  أنثى → ينتقل إلى women_members فقط (يخرج من الشجرة العامة).
--  ذكر  → ينتقل إلى profiles (الشجرة العامة) ثم ينعكس تلقائياً لشجرة النساء.
create or replace function public.move_child_gender(p_child_id uuid, p_to_gender text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  g text := lower(coalesce(p_to_gender, ''));
  pr public.profiles%rowtype;
  wm public.women_members%rowtype;
  new_id uuid;
begin
  if not public.is_moderator() then
    raise exception 'not_authorized';
  end if;

  if g = 'female' then
    select * into pr from public.profiles where id = p_child_id;
    if not found then
      -- موجود في شجرة النساء أصلاً: تأكيد الجنس أنثى وإزالة الصورة.
      update public.women_members
        set gender = 'female', photo_url = null, avatar_url = null
        where id = p_child_id;
      return p_child_id;
    end if;
    insert into public.women_members(
      id, first_name, full_name, parent_id, gender,
      is_deceased, birth_date, death_date, is_hidden_from_tree, sort_order)
    values (
      gen_random_uuid(), pr.first_name,
      coalesce(nullif(pr.full_name, ''), pr.first_name),
      pr.father_id, 'female',
      coalesce(pr.is_deceased, false), pr.birth_date, pr.death_date,
      coalesce(pr.is_hidden_from_tree, false), coalesce(pr.sort_order, 0))
    returning id into new_id;
    -- حذف من العامة → يحذف نسخته الذكر في شجرة النساء عبر المزامنة.
    delete from public.profiles where id = p_child_id;
    return new_id;

  elsif g = 'male' then
    select * into wm from public.women_members where id = p_child_id;
    if not found then
      update public.profiles set gender = 'male' where id = p_child_id;
      return p_child_id;
    end if;
    insert into public.profiles(
      id, first_name, full_name, father_id, gender, status, role,
      is_deceased, birth_date, death_date, is_hidden_from_tree, sort_order,
      is_phone_verified, is_hr_member)
    values (
      gen_random_uuid(), wm.first_name,
      coalesce(nullif(wm.full_name, ''), wm.first_name),
      wm.parent_id, 'male', 'active', 'member',
      coalesce(wm.is_deceased, false), wm.birth_date, wm.death_date,
      coalesce(wm.is_hidden_from_tree, false), coalesce(wm.sort_order, 0),
      false, false)
    returning id into new_id;
    -- إدراج العامة يُنشئ نسخة ذكر في شجرة النساء (بنفس id) عبر المزامنة.
    delete from public.women_members where id = p_child_id;
    return new_id;
  else
    return p_child_id;
  end if;
end;
$$;

grant execute on function public.move_child_gender(uuid, text) to authenticated;;
