-- العائلة تتغيّر بطلب فقط (طلب المالك)
-- العضو لا يغيّر family_name بنفسه: يرسل طلب family_change، والإدارة (المالك/المدير/
-- المراقب — مجال الشجرة) تعتمده فيُطبَّق عليه وعلى أبنائه عبر set_family_name_cascade.
-- يعيد قفل family_name في حارس الخانات الحساسة (كان فُكّ في 20260922280000).

create or replace function public.trg_profiles_protect_sensitive_columns()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  caller_role text := coalesce(public.current_user_role(), 'anonymous');
  me uuid := public.current_profile_id();
  is_staff boolean;
begin
  if auth.role() = 'service_role'
     or (auth.role() is null and session_user in ('postgres', 'supabase_admin', 'supabase_auth_admin')) then
    return new;
  end if;
  is_staff := caller_role in ('owner', 'admin', 'monitor');

  if caller_role <> 'owner' and (
       new.is_admin is distinct from old.is_admin
    or new.is_hr_member is distinct from old.is_hr_member
    or new.hr_status is distinct from old.hr_status) then
    raise exception 'privileged_column_forbidden' using errcode = '42501';
  end if;

  if coalesce(new.is_approved, false) and not coalesce(old.is_approved, false)
     and caller_role not in ('owner', 'admin', 'monitor', 'supervisor') then
    raise exception 'approval_required' using errcode = '42501';
  end if;

  if old.id = me and not is_staff and coalesce(old.status, 'pending') <> 'pending' and (
       new.is_deceased is distinct from old.is_deceased
    or new.death_date is distinct from old.death_date
    or new.father_id is distinct from old.father_id
    or new.is_hidden_from_tree is distinct from old.is_hidden_from_tree
    or new.family_name is distinct from old.family_name) then
    raise exception 'self_edit_forbidden' using errcode = '42501',
      hint = 'هذه البيانات تتعدل عبر طلب للإدارة';
  end if;

  return new;
end;
$$;

create or replace function public.set_family_name_cascade(p_member_id uuid, p_family text)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  affected int;
begin
  -- التطبيق بعد اعتماد طلب «تغيير العائلة» — للمالك/المدير/المراقب فقط
  if coalesce(public.current_user_role(), '') not in ('owner', 'admin', 'monitor') then
    raise exception 'not_allowed';
  end if;

  with recursive line as (
    select id from public.profiles where id = p_member_id
    union all
    select p.id from public.profiles p join line l on p.father_id = l.id
  )
  update public.profiles
     set family_name = nullif(trim(p_family), '')
   where id in (select id from line);

  get diagnostics affected = row_count;
  return affected;
end;
$function$;
