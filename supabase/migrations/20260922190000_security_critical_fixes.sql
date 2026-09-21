-- إصلاح الثغرات الحرجة الخمس من فحص السيرفر (2026-09-22)
-- كل تعديل هنا يغلق طريقاً كان مفتوحاً من السيرفر رغم أن التطبيق لا يعرضه.

-- ─────────────────────────────────────────────────────────────────────────
-- ١) حماية خانات حساسة في profiles
-- سياسة «المستخدم يعدل بياناته فقط» تسمح للعضو بتعديل أي عمود في سجله.
-- الحارس هنا يرفض تغيير (القيمة نفسها تمر — التطبيق يعيد إرسالها عند الحفظ):
--   • is_admin / is_hr_member / hr_status — للمالك فقط
--   • is_approved إلى true — لفريق الإدارة فقط
--   • في سجلك أنت وأنت عضو مفعّل (لا إداري): متوفى، تاريخ الوفاة، الأب،
--     الإخفاء من الشجرة، اسم العائلة. (المسجّل الجديد pending يحددها عند التسجيل،
--     وتعديل الأب لأبنائه يبقى كما هو)
-- ─────────────────────────────────────────────────────────────────────────
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

drop trigger if exists trg_profiles_protect_sensitive_columns on public.profiles;
create trigger trg_profiles_protect_sensitive_columns
  before update on public.profiles
  for each row execute function public.trg_profiles_protect_sensitive_columns();

-- السياسة المكررة (بلا WITH CHECK) — profiles_update_self_or_moderator تغطي نفس الحالة
drop policy if exists "المستخدم يعدل بياناته فقط" on public.profiles;

-- ─────────────────────────────────────────────────────────────────────────
-- ٢) الهوية من app_metadata فقط — user_metadata يعدّله المستخدم بنفسه
-- (current_profile_id يقرأ app_metadata ثم auth.uid)
-- ─────────────────────────────────────────────────────────────────────────
create or replace function public.resolve_profile_id()
returns uuid
language sql
stable security definer
set search_path to 'public', 'auth'
as $$
  select public.current_profile_id();
$$;

create or replace function public.is_hr_or_owner()
returns boolean
language plpgsql
security definer
set search_path to 'public', 'auth'
as $$
begin
  return exists (
    select 1 from public.profiles
    where id = public.current_profile_id()
      and (is_hr_member = true or role = 'owner')
  );
end;
$$;

create or replace function public.get_members_last_signin()
returns table(member_id uuid, last_sign_in_at timestamptz)
language plpgsql
security definer
set search_path to 'public', 'auth'
as $$
declare
  caller_role text;
begin
  select role into caller_role from public.profiles where id = public.current_profile_id();
  if caller_role is null or caller_role not in ('owner', 'admin', 'monitor', 'supervisor') then
    return;
  end if;

  return query
  with all_activity as (
    select u.id as mid, u.last_sign_in_at as ts
    from auth.users u
    where u.last_sign_in_at is not null
    union all
    -- دخول username: الربط من app_metadata (لا يعدّله المستخدم)
    select (u.raw_app_meta_data ->> 'profile_id')::uuid as mid, u.last_sign_in_at as ts
    from auth.users u
    where u.raw_app_meta_data ->> 'profile_id' is not null
      and u.last_sign_in_at is not null
    union all
    select dt.member_id as mid, dt.updated_at as ts
    from public.device_tokens dt
    where dt.updated_at is not null
  )
  select a.mid, max(a.ts)
  from all_activity a
  where a.mid is not null
  group by a.mid;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- ٣) adopt_tree_profile — داخلية فقط (تستدعيها triggers الربط بصلاحياتها)
-- ─────────────────────────────────────────────────────────────────────────
revoke execute on function public.adopt_tree_profile(uuid, uuid) from public, anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- ٤) المحتوى الجديد ينتظر الموافقة — لا نشر أو اعتماد ذاتي من السيرفر
-- يطابق التطبيق: المالك/المدير يعتمدون؛ الإداريون ينشرون أخبارهم وديوانياتهم
-- مباشرة؛ والأعضاء ينشرون الأخبار مباشرة فقط إذا أُطفئت «مراجعة الأخبار».
-- تغيير الحالة لاحقاً للمالك/المدير فقط (غيرهم يقدر يرجعها «pending» عند التعديل).
-- ─────────────────────────────────────────────────────────────────────────
create or replace function public.trg_content_force_pending()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  caller_role text := coalesce(public.current_user_role(), 'anonymous');
  allowed boolean;
begin
  if auth.role() = 'service_role'
     or (auth.role() is null and session_user in ('postgres', 'supabase_admin', 'supabase_auth_admin')) then
    return new;
  end if;

  if caller_role in ('owner', 'admin') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    allowed := (tg_table_name in ('news', 'diwaniyas') and caller_role in ('monitor', 'supervisor'))
      or (tg_table_name = 'news' and exists (
            select 1 from public.app_settings where news_requires_approval = false));
    if coalesce(new.approval_status, 'pending') <> 'pending' and not allowed then
      new.approval_status := 'pending';
      new.approved_by := null;
      if tg_table_name <> 'projects' then new.approved_at := null; end if;
    end if;
    return new;
  end if;

  -- UPDATE
  if new.approval_status is distinct from old.approval_status
     and new.approval_status <> 'pending' then
    raise exception 'approval_forbidden' using errcode = '42501',
      hint = 'الاعتماد للإدارة فقط';
  end if;
  return new;
end;
$$;

do $$
declare t text;
begin
  foreach t in array array['news', 'projects', 'diwaniyas', 'family_archive'] loop
    execute format('drop trigger if exists trg_content_force_pending on public.%I', t);
    execute format('create trigger trg_content_force_pending before insert or update of approval_status on public.%I
                    for each row execute function public.trg_content_force_pending()', t);
  end loop;
end $$;

-- ─────────────────────────────────────────────────────────────────────────
-- ٥) تحرير رقم جوال — لرقمك أنت فقط (الموثّق بـ OTP)
-- ─────────────────────────────────────────────────────────────────────────
create or replace function public.free_phone_for_reregistration(p_phone text, p_new_member_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
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
$$;

revoke execute on function public.free_phone_for_reregistration(text, uuid) from public, anon;
grant execute on function public.free_phone_for_reregistration(text, uuid) to authenticated;

-- الإدراج برقم عضو آخر: يُحرَّر الرقم فقط لفريق الإدارة أو لصاحب الرقم الموثّق؛
-- غير ذلك يُرفض (بدل أن يُسحب الرقم من صاحبه بصمت)
create or replace function public.trg_profiles_free_conflicting_phone()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_conflicting_id uuid;
  v_auth_phone text;
  caller_role text := coalesce(public.current_user_role(), 'anonymous');
begin
  if new.phone_number is null or trim(new.phone_number) = '' then
    return new;
  end if;

  select id into v_conflicting_id
  from public.profiles
  where phone_number = new.phone_number and id <> new.id
  limit 1;

  if v_conflicting_id is null then
    return new;
  end if;

  if not (
       auth.role() = 'service_role'
    or auth.uid() is null
    or caller_role in ('owner', 'admin', 'monitor')
  ) then
    select regexp_replace(coalesce(phone, ''), '[^0-9]', '', 'g') into v_auth_phone
    from auth.users where id = auth.uid();
    if new.id <> auth.uid()
       or v_auth_phone = ''
       or regexp_replace(new.phone_number, '[^0-9]', '', 'g') <> v_auth_phone then
      raise exception 'phone_in_use' using errcode = '23505',
        hint = 'هذا الرقم مسجّل لعضو آخر';
    end if;
  end if;

  update public.profiles set phone_number = null where id = v_conflicting_id;
  return new;
end;
$$;
