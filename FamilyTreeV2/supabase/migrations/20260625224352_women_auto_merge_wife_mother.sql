-- دمج تلقائي: عند إضافة زوجة، أي "أم منفصلة" بنفس الاسم الأول هي أمّ لأحد
-- أبناء هذا الزوج = نفس الشخص → تُنقل أمومتها للزوجة الجديدة ثم تُحذف.
create or replace function public.women_auto_merge_wife()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  dup_ids uuid[];
begin
  if new.husband_id is null or lower(coalesce(new.gender, '')) <> 'female' then
    return new;
  end if;

  -- أمّهات منفصلات (بلا زوج) بنفس الاسم الأول وهنّ أمّهات لأبناء هذا الزوج.
  dup_ids := array(
    select distinct m.id
    from public.women_members m
    join public.women_members c
      on c.mother_id = m.id and c.parent_id = new.husband_id
    where m.husband_id is null
      and m.id <> new.id
      and m.first_name = new.first_name
  );

  if array_length(dup_ids, 1) is null then
    return new;
  end if;

  -- انقل أمومة أبناء هذا الزوج إلى الزوجة الجديدة.
  update public.women_members
     set mother_id = new.id
   where parent_id = new.husband_id
     and mother_id = any(dup_ids);

  -- احذف السجلات المنفصلة المكررة.
  delete from public.women_members where id = any(dup_ids);

  return new;
end;
$$;

drop trigger if exists trg_women_auto_merge_wife on public.women_members;
create trigger trg_women_auto_merge_wife
after insert on public.women_members
for each row
execute function public.women_auto_merge_wife();;
