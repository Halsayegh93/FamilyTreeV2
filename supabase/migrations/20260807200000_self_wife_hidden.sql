-- خيار «الإخفاء من الشجرة» لزوجة العضو — يضيفها/يعدّلها العضو لنفسه.
-- الإخفاء يمنع ظهورها لأي أحد في الشجرة (is_hidden_from_tree).

-- إضافة زوجة بالاسم مع خيار الإخفاء. الافتراضي false فتبقى النداءات القديمة صالحة.
drop function if exists public.add_self_wife(text);
create or replace function public.add_self_wife(p_name text, p_hidden boolean default false)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare me uuid := public.my_women_node(); nid uuid := gen_random_uuid(); nm text := trim(coalesce(p_name,''));
begin
  if me is null then raise exception 'no_node'; end if;
  if nm = '' then raise exception 'name_required'; end if;
  insert into public.women_members(id, first_name, full_name, husband_id, gender, sort_order,
                                   is_married, is_hidden_from_tree)
    values (nid, nm, nm, me, 'female', 0, true, coalesce(p_hidden, false));
  return nid;
end; $$;

-- تبديل إخفاء زوجة العضو — مقيَّد بزوجاته هو فقط.
create or replace function public.set_self_wife_hidden(p_wife_id uuid, p_hidden boolean)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare me uuid := public.my_women_node();
begin
  if me is null then raise exception 'no_node'; end if;
  if not exists (
    select 1 from public.women_members where id = p_wife_id and husband_id = me
  ) then raise exception 'not_your_wife'; end if;
  update public.women_members
     set is_hidden_from_tree = coalesce(p_hidden, false)
   where id = p_wife_id;
end; $$;

revoke all on function public.add_self_wife(text, boolean) from public, anon;
revoke all on function public.set_self_wife_hidden(uuid, boolean) from public, anon;
grant execute on function public.add_self_wife(text, boolean) to authenticated;
grant execute on function public.set_self_wife_hidden(uuid, boolean) to authenticated;
