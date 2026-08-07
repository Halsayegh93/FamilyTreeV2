-- ترتيب أبناء العضو (profiles) في طلب واحد بدل تحديث لكل ابن على حدة.
-- كان العميل يرسل UPDATE متسلسلاً لكل ابن مع كل ضغطة سهم، فالترتيب بطيء.
-- مقيَّد على أبناء المستخدم نفسه (father_id = auth.uid()).
create or replace function public.reorder_self_children(p_ids uuid[])
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not_authenticated'; end if;
  update public.profiles p
     set sort_order = x.ord - 1
    from unnest(p_ids) with ordinality as x(id, ord)
   where p.id = x.id
     and p.father_id = me;
end; $$;

revoke all on function public.reorder_self_children(uuid[]) from public, anon;
grant execute on function public.reorder_self_children(uuid[]) to authenticated;
