begin;
create function public.admin_membership_counts()
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
  if coalesce(public.current_user_role(),'') not in ('owner','admin') then
    raise exception 'not_authorized' using errcode='42501';
  end if;
  return (
    select jsonb_build_object(
      'total_members',count(*)::int,
      'in_system',count(*) filter (where exists (
        select 1 from auth.users u
        where lower(coalesce(nullif(u.raw_app_meta_data->>'profile_id',''),u.id::text))=p.id::text
          and u.last_sign_in_at is not null
      ))::int,
      'checked_at',now())
    from public.profiles p
    where p.is_deceased is not true and p.status='active'
      and p.role in ('owner','admin','monitor','supervisor','member')
  );
end $$;
revoke all on function public.admin_membership_counts() from public,anon;
grant execute on function public.admin_membership_counts() to authenticated;
commit;
