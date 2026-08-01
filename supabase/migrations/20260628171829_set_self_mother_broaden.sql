-- توسيع اختيار الأم: تُقبل إذا كانت زوجة للأب، أو أمّ لأحد الإخوة (نفس الأب).
create or replace function public.set_self_mother(p_mother_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := public.my_women_node(); fid uuid; ok boolean;
begin
  if me is null then raise exception 'no_node'; end if;
  select parent_id into fid from public.women_members where id = me;
  if p_mother_id is not null then
    select exists(
      select 1 from public.women_members w
      where w.id = p_mother_id and (
        w.husband_id = fid
        or exists(select 1 from public.women_members s
                  where s.parent_id = fid and s.mother_id = p_mother_id)
      )
    ) into ok;
    if not coalesce(ok, false) then raise exception 'not_father_wife'; end if;
  end if;
  update public.women_members set mother_id = p_mother_id where id = me;
end; $$;;
