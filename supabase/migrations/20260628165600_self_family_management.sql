-- إدارة العضو لعائلته الخاصة (الأم/الزوجة) في شجرة النساء — بدون صلاحية إدارة.
-- عقدة المستخدم في شجرة النساء (الذكر: نفس المعرّف؛ الأنثى: linked_user_id).
create or replace function public.my_women_node()
returns uuid language sql security definer set search_path = public stable as $$
  select id from public.women_members
  where id = auth.uid() or linked_user_id = auth.uid()
  limit 1;
$$;

-- إضافة زوجة للمستخدم نفسه.
create or replace function public.add_self_wife(p_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare me uuid := public.my_women_node(); nid uuid := gen_random_uuid(); nm text := trim(coalesce(p_name,''));
begin
  if me is null then raise exception 'no_node'; end if;
  if nm = '' then raise exception 'name_required'; end if;
  insert into public.women_members(id, first_name, full_name, husband_id, gender, sort_order)
    values (nid, nm, nm, me, 'female', 0);
  return nid;
end; $$;

-- إضافة أمّ للمستخدم — زوجة لأبيه + ربطها mother_id به.
create or replace function public.add_self_mother(p_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare me uuid := public.my_women_node(); fid uuid; nid uuid := gen_random_uuid(); nm text := trim(coalesce(p_name,''));
begin
  if me is null then raise exception 'no_node'; end if;
  if nm = '' then raise exception 'name_required'; end if;
  select parent_id into fid from public.women_members where id = me;
  if fid is null then raise exception 'no_father'; end if;
  insert into public.women_members(id, first_name, full_name, husband_id, gender, sort_order)
    values (nid, nm, nm, fid, 'female', 0);
  update public.women_members set mother_id = nid where id = me;
  return nid;
end; $$;

-- اختيار أمّ موجودة (لازم تكون إحدى زوجات الأب) أو إزالتها.
create or replace function public.set_self_mother(p_mother_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := public.my_women_node(); fid uuid; ok boolean;
begin
  if me is null then raise exception 'no_node'; end if;
  select parent_id into fid from public.women_members where id = me;
  if p_mother_id is not null then
    select exists(select 1 from public.women_members w where w.id = p_mother_id and w.husband_id = fid) into ok;
    if not coalesce(ok,false) then raise exception 'not_father_wife'; end if;
  end if;
  update public.women_members set mother_id = p_mother_id where id = me;
end; $$;

grant execute on function public.my_women_node() to authenticated;
grant execute on function public.add_self_wife(text) to authenticated;
grant execute on function public.add_self_mother(text) to authenticated;
grant execute on function public.set_self_mother(uuid) to authenticated;;
