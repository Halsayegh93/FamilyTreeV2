-- اسم العائلة يعدّله العضو من «تعديل الملف الشخصي» (طلب المالك)
-- حارس الخانات الحساسة (20260922190000) كان يمنع العضو من تغيير family_name في سجله،
-- فيفشل اختيار العائلة (set_family_name_cascade يحدّث سجلك وأبناءك معاً).
-- العائلة اختيار من قائمة الإدارة المعتمدة — لا خطر، فتُزال من القفل.

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
    or new.is_hidden_from_tree is distinct from old.is_hidden_from_tree) then
    raise exception 'self_edit_forbidden' using errcode = '42501',
      hint = 'هذه البيانات تتعدل عبر طلب للإدارة';
  end if;

  return new;
end;
$$;
