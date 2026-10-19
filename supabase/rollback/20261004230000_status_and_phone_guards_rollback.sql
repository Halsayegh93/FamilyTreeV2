-- التراجع عن 20261004230000_status_and_phone_guards — يعيد الدوال الثلاث كما كانت على السيرفر الحي
-- قبل التطبيق (٢٠٢٦-١٠-٠٤، منسوخة من pg_get_functiondef ومطابقة بـ md5(prosrc)).

CREATE OR REPLACE FUNCTION public.prepare_phone_unlink(p_profile_id uuid)
 RETURNS uuid[]
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare ids uuid[]; target_role text;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'service_only' using errcode='42501'; end if;
  select role into target_role from public.profiles where id=p_profile_id for update;
  if not found then raise exception 'profile_not_found'; end if;
  if target_role='owner' then raise exception 'owner_account_protected' using errcode='42501'; end if;
  select coalesce(array_agg(id),'{}'::uuid[]) into ids from auth.users
    where id=p_profile_id or raw_app_meta_data->>'profile_id'=p_profile_id::text;
  update public.profiles set phone_number=null,status='pending' where id=p_profile_id;
  delete from public.device_tokens where member_id=p_profile_id or member_id=any(ids);
  return ids;
end;
$function$;

CREATE OR REPLACE FUNCTION public.prevent_role_self_promotion()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.free_phone_for_reregistration(p_phone text, p_new_member_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_normalized text;
  v_auth_phone text;
  v_old_id uuid;
begin
  -- المتصل يحرر الرقم لسجله هو فقط، والرقم لازم يكون رقم دخوله الموثّق
  if auth.uid() is null or p_new_member_id is distinct from auth.uid() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  v_normalized := regexp_replace(trim(p_phone), '[^0-9+]', '', 'g');
  select regexp_replace(coalesce(phone, ''), '[^0-9]', '', 'g') into v_auth_phone
  from auth.users where id = auth.uid();
  if v_auth_phone = '' or regexp_replace(v_normalized, '[^0-9]', '', 'g') <> v_auth_phone then
    raise exception 'phone_not_verified' using errcode = '42501';
  end if;

  select id into v_old_id
  from public.profiles
  where phone_number = v_normalized and id <> p_new_member_id
  limit 1;

  if v_old_id is not null then
    update public.profiles set phone_number = null where id = v_old_id;

    insert into public.notifications (target_member_id, title, body, kind, created_by)
    select p.id,
           'تعارض رقم عند التسجيل',
           format('الرقم %s كان مرتبطاً بعضو في الشجرة وتم تحريره للتسجيل الجديد. يُرجى مراجعة الطلب وإجراء الدمج إذا لزم.', v_normalized),
           'admin_request',
           p_new_member_id
    from public.profiles p
    where p.role in ('owner', 'admin', 'monitor', 'supervisor') and p.status = 'active';
  end if;
end;
$function$;
