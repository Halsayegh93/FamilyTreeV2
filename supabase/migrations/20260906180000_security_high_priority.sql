begin;

-- A single server-owned identity; never fall back to user_metadata.
create or replace function public.current_profile_id()
returns uuid language sql stable set search_path = public as $$
  select case when auth.uid() is null then null else coalesce(
    nullif(auth.jwt()->'app_metadata'->>'profile_id', '')::uuid, auth.uid()) end;
$$;
revoke all on function public.current_profile_id() from public, anon;
grant execute on function public.current_profile_id() to authenticated, service_role;

create or replace function public.current_user_role()
returns text language sql stable security definer set search_path = public as $$
  select case when p.status = 'active' then p.role when p.status in ('frozen','deleted') then p.status else 'pending' end
  from public.profiles p where p.id = public.current_profile_id();
$$;

create or replace function public.is_approved_member()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.current_user_role() = any(array['member','supervisor','monitor','admin','owner']), false);
$$;
revoke all on function public.is_approved_member() from public, anon;
grant execute on function public.is_approved_member() to authenticated, service_role;

create or replace function public.prevent_role_self_promotion()
returns trigger language plpgsql security definer set search_path = public as $$
declare caller_role text := coalesce(public.current_user_role(), 'anonymous'); me uuid := public.current_profile_id();
begin
  -- The service role is server-only. SQL maintenance has no JWT role.
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
    if caller_role = 'owner' and old.id <> me then
      null;
    elsif old.role = 'pending' and new.role = 'member' and new.status = 'active'
      and old.id <> me and caller_role in ('admin','monitor','supervisor') then
      -- Row policy also restricts supervisors to their branch.
      null;
    elsif old.id = me and old.role = 'member' and new.role = 'pending' and new.status = 'pending' then
      null;
    else raise exception 'role_change_forbidden' using errcode = '42501';
    end if;
  end if;
  if new.status is distinct from old.status then
    if caller_role in ('owner','admin','monitor') and old.id <> me then null;
    elsif caller_role = 'supervisor' and old.id <> me and old.status = 'pending'
      and new.status = 'active' and new.role = 'member' then null;
    elsif old.id = me and old.status = 'active' and new.status = 'pending' and new.role = 'pending' then null;
    else raise exception 'status_change_forbidden' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_prevent_role_self_promotion on public.profiles;
create trigger trg_prevent_role_self_promotion before insert or update on public.profiles
for each row execute function public.prevent_role_self_promotion();

create or replace function public.get_member_phone(p_id uuid)
returns text language plpgsql stable security definer set search_path = public as $$
declare me uuid := public.current_profile_id(); r record;
begin
  if me is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if not public.is_approved_member() then return null; end if;
  select phone_number, coalesce(is_phone_hidden,false) as hidden into r from public.profiles where id = p_id;
  if not found then return null; end if;
  if p_id = me or public.current_user_role() in ('owner','admin','monitor','supervisor') or not r.hidden then
    return r.phone_number;
  end if;
  return null;
end;
$$;
revoke all on function public.get_member_phone(uuid) from public, anon;
grant execute on function public.get_member_phone(uuid) to authenticated;

create or replace function public.reorder_self_children(p_ids uuid[])
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := public.current_profile_id();
begin
  if me is null or not public.is_approved_member() then
    raise exception 'approval_required' using errcode = '42501';
  end if;
  update public.profiles p set sort_order = x.ord - 1
  from unnest(p_ids) with ordinality as x(id,ord) where p.id = x.id and p.father_id = me;
end;
$$;
revoke all on function public.reorder_self_children(uuid[]) from public, anon;
grant execute on function public.reorder_self_children(uuid[]) to authenticated;
commit;
