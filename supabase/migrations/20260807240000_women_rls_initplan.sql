-- سياسة women_members_select كانت تستدعي my_women_node()/current_user_role()
-- لكل صف (STABLE لا تُخزَّن تلقائياً في الشرط) — ~12 ألف استدعاء لكل قراءة
-- للشجرة. لفّها في استعلام قياسي يجعلها InitPlan يُقيَّم مرّة واحدة.
drop policy if exists women_members_select on public.women_members;
create policy women_members_select on public.women_members
for select to authenticated
using (
  is_hidden_from_tree = false
  or (select public.current_user_role()) = any (array['owner','admin','monitor'])
  or id         = (select public.my_women_node())
  or husband_id = (select public.my_women_node())
  or parent_id  = (select public.my_women_node())
  or mother_id  = (select public.my_women_node())
);
