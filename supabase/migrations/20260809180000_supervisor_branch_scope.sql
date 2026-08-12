create or replace function public.is_in_supervisor_branch(p_target uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $fn$
  with recursive me as (
    select coalesce(
      nullif(auth.jwt() -> 'app_metadata' ->> 'profile_id', '')::uuid,
      auth.uid()) as id
  ),
  roots as (
    select bs.branch_root_id from public.branch_supervisors bs, me
     where bs.supervisor_id = me.id
  ),
  chain as (
    select p.id, p.father_id, 1 as depth from public.profiles p where p.id = p_target
    union all
    select p.id, p.father_id, c.depth + 1
      from public.profiles p join chain c on p.id = c.father_id
     where c.depth < 60
  )
  select exists (select 1 from chain where chain.id in (select branch_root_id from roots));
$fn$;

revoke all on function public.is_in_supervisor_branch(uuid) from public, anon;
grant execute on function public.is_in_supervisor_branch(uuid) to authenticated;

-- تقييد المشرف بفرعه: كان دور supervisor في قائمة المشرفين المطلقة، فيعدّل
-- ويضيف أي عضو في العائلة، وتعيينه في branch_supervisors بلا أثر.
-- UPDATE: المشرف يعدّل داخل فرعه فقط؛ بقية الأدوار كما هي
alter policy profiles_update_self_or_moderator on public.profiles
  using (
    id = auth.uid()
    or current_user_role() = any (array['owner','admin','monitor'])
    or (current_user_role() = 'supervisor' and is_in_supervisor_branch(id))
    or is_descendant_of_caller(id)
  )
  with check (
    id = auth.uid()
    or current_user_role() = any (array['owner','admin','monitor'])
    or (current_user_role() = 'supervisor' and is_in_supervisor_branch(id))
    or is_descendant_of_caller(id)
  );

-- INSERT: المشرف يضيف تحت فرعه فقط (الأب داخل نطاقه)
alter policy profiles_insert_guarded on public.profiles
  with check (
    current_user_role() = any (array['owner','admin','monitor'])
    or (current_user_role() = 'supervisor' and father_id is not null and is_in_supervisor_branch(father_id))
    or (coalesce(role,'pending') = any (array['pending','member'])
        and (id = auth.uid() or father_id = auth.uid() or is_descendant_of_caller(father_id)))
  );
