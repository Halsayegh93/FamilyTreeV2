-- بقايا فحص الثغرات بعد إصلاحات التطبيقات (٢٠٢٦-١٠-٠٤) — بموافقة المالك على البنود الثلاثة:
-- ١) فك الرقم لا يفك التجميد: prepare_phone_unlink كانت ترجع أي عضو «معلّقاً» — المجمّد والمحذوف يبقيان.
-- ٢) المراقب يفعّل فقط: كان السيرفر يسمح للمراقب بتغيير حالة أي عضو (تجميد وفك تجميد)، وجدول الأدوار
--    يجعل التجميد للمالك والمدير. المراقب: من «معلّق» (أو بلا حالة) إلى «مفعّل» كعضو فقط — قبول
--    الانضمام، إضافة الرقم، إضافة ابن. أزرار التجميد في التطبيقين للمالك والمدير أصلاً (canFreezeMembers).
-- ٣) free_phone_for_reregistration (تستدعيها النسخ القديمة عند التسجيل) كانت تفرّغ الرقم من أي ملف — ولو
--    لأحد الإدارة أو لعضو له حساب دخول. الآن نفس قاعدة مشغّل الإدراج trg_profiles_free_conflicting_phone:
--    لا تحرير لرقم إداري أو مربوط بحساب (phone_in_use).
-- التراجع: supabase/rollback/20261004230000_status_and_phone_guards_rollback.sql
-- التجربة المحلية: cd supabase/tests/family_links && node status_and_phone_guards.test.mjs

create or replace function public.prepare_phone_unlink(p_profile_id uuid)
 returns uuid[]
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare ids uuid[]; target_role text;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'service_only' using errcode='42501'; end if;
  select role into target_role from public.profiles where id=p_profile_id for update;
  if not found then raise exception 'profile_not_found'; end if;
  if target_role='owner' then raise exception 'owner_account_protected' using errcode='42501'; end if;
  select coalesce(array_agg(id),'{}'::uuid[]) into ids from auth.users
    where id=p_profile_id or raw_app_meta_data->>'profile_id'=p_profile_id::text;
  -- المجمّد والمحذوف يبقيان كما هما — فك الرقم لا يفك التجميد
  update public.profiles
     set phone_number=null,
         status=case when status in ('frozen','deleted') then status else 'pending' end
   where id=p_profile_id;
  delete from public.device_tokens where member_id=p_profile_id or member_id=any(ids);
  return ids;
end;
$function$;

create or replace function public.prevent_role_self_promotion()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
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
    if caller_role in ('owner','admin') and old.id <> me then null;
    -- المراقب يفعّل فقط (٢٠٢٦-١٠-٠٤): التجميد وفكّه للمالك والمدير كما في جدول الأدوار
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

create or replace function public.free_phone_for_reregistration(p_phone text, p_new_member_id uuid)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
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
    -- لا تحرير لرقم أحد الإدارة أو لعضو له حساب دخول (نفس قاعدة trg_profiles_free_conflicting_phone)
    if exists (select 1 from public.profiles h
               where h.id = v_old_id and h.role in ('owner', 'admin', 'monitor', 'supervisor'))
       or exists (select 1 from auth.users u where u.id = v_old_id)
       or exists (select 1 from auth.users u
                  where coalesce(u.raw_app_meta_data->>'profile_id', '') = v_old_id::text) then
      raise exception 'phone_in_use' using errcode = '23505',
        hint = 'هذا الرقم مسجّل لعضو آخر';
    end if;

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
