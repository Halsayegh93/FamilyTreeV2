-- Critical authorization hardening.
-- This migration is intentionally additive so it can be reviewed before deploy.

create or replace function public.current_user_can_moderate()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and role in ('owner', 'admin', 'monitor', 'supervisor')
      and coalesce(status, 'active') not in ('frozen', 'deleted')
  );
$$;

revoke all on function public.current_user_can_moderate() from public;
grant execute on function public.current_user_can_moderate() to authenticated;

-- A later migration accidentally made broadcast notifications visible to every
-- authenticated user. Broadcast rows are administrative; only moderators may
-- read them, while personal rows remain visible to their target member.
drop policy if exists "notifications_select_target_or_all_or_moderator"
on public.notifications;

create policy "notifications_select_target_or_all_or_moderator"
on public.notifications
for select
to authenticated
using (
  target_member_id = auth.uid()
  or (
    target_member_id is null
    and public.current_user_can_moderate()
  )
);

-- Remove legacy broad INSERT policies, including names observed in remote dumps.
drop policy if exists "profiles_insert_self" on public.profiles;
drop policy if exists "profiles_insert_authenticated" on public.profiles;
drop policy if exists "Allow authenticated users to insert profiles" on public.profiles;
drop policy if exists "Allow system to link profiles" on public.profiles;

create policy "profiles_insert_guarded"
on public.profiles
for insert
to authenticated
with check (
  -- A user may create only their own pending registration profile.
  (
    id = auth.uid()
    and role = 'pending'
    and status = 'pending'
    and coalesce(is_approved, false) = false
  )
  -- An active member may add a direct child under their own profile.
  or (
    father_id = auth.uid()
    and role = 'member'
    and status = 'active'
  )
  -- Moderation roles may add or link tree members.
  or public.current_user_can_moderate()
);

create or replace function public.merge_member_into_tree(
  p_new_member_id uuid,
  p_tree_member_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new public.profiles%rowtype;
  v_tree public.profiles%rowtype;
begin
  if auth.uid() is null or not public.current_user_can_moderate() then
    raise exception 'insufficient privileges'
      using errcode = '42501';
  end if;

  if p_new_member_id = p_tree_member_id then
    return jsonb_build_object(
      'success', false,
      'message', 'لا يمكن دمج العضو مع نفسه'
    );
  end if;

  select * into v_new
  from public.profiles
  where id = p_new_member_id
  for update;

  select * into v_tree
  from public.profiles
  where id = p_tree_member_id
  for update;

  if v_new.id is null then
    return jsonb_build_object(
      'success', false,
      'message', 'سجل العضو الجديد غير موجود'
    );
  end if;

  if v_tree.id is null then
    return jsonb_build_object(
      'success', false,
      'message', 'سجل عضو الشجرة غير موجود'
    );
  end if;

  update public.profiles set
    role = 'member',
    status = 'active',
    is_hidden_from_tree = false,
    full_name = v_tree.full_name,
    first_name = v_tree.first_name,
    father_id = v_tree.father_id,
    sort_order = v_tree.sort_order,
    is_deceased = coalesce(v_tree.is_deceased, false),
    is_married = coalesce(v_tree.is_married, false),
    birth_date = coalesce(v_tree.birth_date, v_new.birth_date),
    death_date = v_tree.death_date,
    gender = coalesce(v_tree.gender, v_new.gender),
    bio = coalesce(v_tree.bio, v_new.bio),
    avatar_url = coalesce(nullif(v_tree.avatar_url, ''), v_new.avatar_url),
    cover_url = coalesce(nullif(v_tree.cover_url, ''), v_new.cover_url),
    photo_url = coalesce(nullif(v_tree.photo_url, ''), v_new.photo_url)
  where id = p_new_member_id;

  update public.profiles
  set father_id = p_new_member_id
  where father_id = p_tree_member_id;

  update public.member_gallery_photos
  set member_id = p_new_member_id
  where member_id = p_tree_member_id;

  update public.notifications
  set target_member_id = p_new_member_id
  where target_member_id = p_tree_member_id;

  update public.admin_requests
  set status = 'approved'
  where member_id = p_new_member_id
    and request_type in ('join_request', 'link_request')
    and status = 'pending';

  delete from public.admin_requests
  where member_id = p_tree_member_id
     or requester_id = p_tree_member_id;

  update public.device_tokens
  set member_id = p_new_member_id
  where member_id = p_tree_member_id;

  delete from public.profiles
  where id = p_tree_member_id;

  return jsonb_build_object(
    'success', true,
    'message', format('تم دمج %s بنجاح وتفعيل حسابه', v_tree.full_name),
    'merged_name', v_tree.full_name
  );
exception
  when insufficient_privilege then
    raise;
  when others then
    return jsonb_build_object(
      'success', false,
      'message', format('فشل الدمج: %s', sqlerrm)
    );
end;
$$;

revoke all on function public.merge_member_into_tree(uuid, uuid) from public;
grant execute on function public.merge_member_into_tree(uuid, uuid) to authenticated;
