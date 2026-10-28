-- تراجع 20261027190000_self_relatives: يعيد التعريفات السابقة كما كانت حية في ٢٠٢٦-١٠-٢٧.
create or replace function public.my_women_node()
 returns uuid language sql stable security definer set search_path to 'public'
as $function$
  select id from public.women_members
  where id = auth.uid() or linked_user_id = auth.uid()
  limit 1;
$function$;

create or replace function public.is_descendant_of_caller(target uuid)
 returns boolean language sql stable security definer set search_path to 'public'
as $function$
  with recursive ancestors as (
    select father_id as ancestor_id from public.profiles where id = target
    union all
    select p.father_id from public.profiles p join ancestors a on p.id = a.ancestor_id where p.father_id is not null
  )
  select coalesce((select status = 'active' from public.profiles where id = auth.uid()), false)
  and coalesce((select exists (select 1 from ancestors where ancestor_id = auth.uid())), false);
$function$;

create or replace function public.prevent_role_self_promotion()
 returns trigger language plpgsql security definer set search_path to 'public'
as $function$
declare caller_role text := coalesce(public.current_user_role(), 'anonymous'); me uuid := public.current_profile_id();
begin
  if auth.role() = 'service_role' or (auth.role() is null and session_user in ('postgres','supabase_admin','supabase_auth_admin')) then
    return new;
  end if;
  if me is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if tg_op = 'INSERT' then
    if coalesce(new.role,'pending') not in ('pending','member') then
      raise exception 'privileged_role_requires_role_management' using errcode = '42501';
    end if;
    if coalesce(new.status,'pending') <> 'pending' and caller_role not in ('owner','admin','monitor','supervisor') then
      raise exception 'approval_required' using errcode = '42501';
    end if;
    return new;
  end if;
  if caller_role in ('frozen','deleted') then
    raise exception 'account_inactive' using errcode = '42501';
  end if;
  if old.role = 'owner' and (new.role is distinct from old.role or new.status is distinct from old.status) then
    raise exception 'owner_protected' using errcode = '42501';
  end if;
  if new.role = 'owner' and old.role is distinct from 'owner' then
    raise exception 'owner_protected' using errcode = '42501';
  end if;
  if new.role is distinct from old.role then
    if caller_role = 'owner' and old.id <> me then null;
    elsif old.role = 'pending' and new.role = 'member' and new.status = 'active'
      and old.id <> me and caller_role in ('admin','monitor','supervisor') then null;
    elsif old.id = me and old.role = 'member' and new.role = 'pending' and new.status = 'pending' then null;
    else raise exception 'role_change_forbidden' using errcode = '42501';
    end if;
  end if;
  if new.status is distinct from old.status then
    if caller_role in ('owner','admin') and old.id <> me then null;
    elsif caller_role = 'monitor' and old.id <> me and coalesce(old.status, 'pending') = 'pending'
      and new.status = 'active' and new.role = 'member' then null;
    elsif caller_role = 'supervisor' and old.id <> me and old.status = 'pending'
      and new.status = 'active' and new.role = 'member' then null;
    elsif old.id = me and old.status = 'active' and new.status = 'pending' and new.role = 'pending' then null;
    else raise exception 'status_change_forbidden' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$function$;

create or replace function public.add_family_child(p_parent_id uuid, p_name text, p_gender text DEFAULT 'male'::text, p_birth date DEFAULT NULL::date, p_deceased boolean DEFAULT false, p_death date DEFAULT NULL::date, p_sort integer DEFAULT 0, p_parent_full_name text DEFAULT ''::text)
 returns uuid language plpgsql security definer set search_path to 'public'
as $function$
declare
  g text := lower(coalesce(p_gender, 'male'));
  new_id uuid := gen_random_uuid();
  nm text := trim(coalesce(p_name, ''));
  chained text := case when coalesce(trim(p_parent_full_name), '') = '' then nm else nm || ' ' || trim(p_parent_full_name) end;
begin
  if not (coalesce(public.current_user_role(), '') in ('owner', 'admin', 'monitor') or (p_parent_id = any (array[auth.uid(), public.current_profile_id()]) and coalesce(public.current_user_role(), '') in ('member', 'supervisor'))) then
    raise exception 'not_authorized';
  end if;
  if nm = '' then raise exception 'name_required'; end if;
  if g = 'female' then
    insert into public.women_members(id, first_name, full_name, parent_id, gender, is_deceased, birth_date, death_date, sort_order)
    values (new_id, nm, chained, p_parent_id, 'female', coalesce(p_deceased, false), p_birth, case when p_deceased then p_death else null end, coalesce(p_sort, 0));
  else
    insert into public.profiles(id, first_name, full_name, father_id, gender, status, role, is_deceased, birth_date, death_date, sort_order, is_phone_verified, is_hr_member)
    values (new_id, nm, chained, p_parent_id, 'male', 'active', 'member', coalesce(p_deceased, false), p_birth, case when p_deceased then p_death else null end, coalesce(p_sort, 0), false, false);
  end if;
  return new_id;
end;
$function$;

create or replace function public.add_self_mother(p_name text)
 returns uuid language plpgsql security definer set search_path to 'public'
as $function$
declare me uuid := public.my_active_women_node(); fid uuid; nid uuid := gen_random_uuid(); nm text := trim(coalesce(p_name,''));
begin
  if me is null then raise exception 'no_node'; end if;
  if nm = '' then raise exception 'name_required'; end if;
  select parent_id into fid from public.women_members where id = me;
  if fid is null then raise exception 'no_father'; end if;
  insert into public.women_members(id, first_name, full_name, husband_id, gender, sort_order) values (nid, nm, nm, fid, 'female', 0);
  update public.women_members set mother_id = nid where id = me;
  return nid;
end; $function$;

drop function if exists public.set_self_relative_mother(uuid, uuid);
delete from public.app_config where key = 'self_child_daily_limit';
grant execute on function public.set_self_wife(uuid) to authenticated;
