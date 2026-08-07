-- ١) فرض «الإخفاء من الشجرة» على مستوى RLS لا في الواجهة فقط.
--    كانت women_members_select = USING(true) فأي عضو مسجَّل يقدر يقرأ الصف
--    المخفيّ مباشرة من REST/Realtime رغم إخفائه في التطبيق.
--    المخفيّة تبقى مرئية لـ: الإدارة · نفسها · زوجها · أبواها.
drop policy if exists women_members_select on public.women_members;
create policy women_members_select on public.women_members
for select to authenticated
using (
  is_hidden_from_tree = false
  or public.current_user_role() = any (array['owner','admin','monitor'])
  or id         = public.my_women_node()
  or husband_id = public.my_women_node()
  or parent_id  = public.my_women_node()
  or mother_id  = public.my_women_node()
);

-- ٢) reorder_self_children كانت تعتمد auth.uid() وحدها، فلا تعمل لمن
--    معرّف ملفّه في claim منفصل (حساب واحد اليوم) — تُرتّب صفراً بصمت.
create or replace function public.reorder_self_children(p_ids uuid[])
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare me uuid := coalesce(
    nullif(auth.jwt() -> 'app_metadata' ->> 'profile_id', '')::uuid,
    nullif(auth.jwt() -> 'user_metadata' ->> 'profile_id', '')::uuid,
    auth.uid());
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
