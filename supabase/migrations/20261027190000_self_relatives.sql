-- العضو يضيف أقاربه بنفسه والإدارة تسهّل الربط فقط — قرار المالك ٢٠٢٦-١٠-٢٧
-- («رقم١ ويصل اشعار فقط ما يحتاج موافق / ٢- لا / ٣- طلب / ٤- نعم»). المرجع: drafts/self-relatives-audit-2026-10-27.md
--  س١  عقدة العضو في شجرة النساء بـ current_profile_id() (الحساب المنقول كان يرجع no_node)، ونفسها في is_descendant_of_caller.
--  س٢  الابن مباشر: add_family_child الذكر للعضو لنفسه يُدرج مفعّلاً + إشعار للمالك والمدير، بحدّ يومي من app_config.
--  س٣/٤ set_self_relative_mother: العضو يربط أبناءه/بناته بأمهم (زوجته)، وأخواته بأمهن (زوجة أبيه).
--  س٥  add_self_mother لا يستبدل أماً موجودة (التغيير عبر set_self_mother).
--  س٧  set_self_wife مغلقة (لا يستدعيها تطبيق وتربط أي امرأة بلا شروط).
-- الوفاة للزوجة/الأم/الأخت تبقى طلباً (قرار ٣) — لا تغيير.
-- التراجع: supabase/rollback/20261027190000_self_relatives_rollback.sql

-- ───────── س١ ─────────
create or replace function public.my_women_node()
 returns uuid
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select w.id from public.women_members w
   where w.id = public.current_profile_id() or w.id = auth.uid() or w.linked_user_id = auth.uid()
   order by (w.id = public.current_profile_id()) desc, (w.id = auth.uid()) desc
   limit 1;
$function$;

create or replace function public.is_descendant_of_caller(target uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  with recursive ancestors as (
    select father_id as ancestor_id
      from public.profiles
     where id = target
    union all
    select p.father_id
      from public.profiles p
      join ancestors a on p.id = a.ancestor_id
     where p.father_id is not null
  )
  select coalesce(
    (select status = 'active' from public.profiles where id = public.current_profile_id()),
    false
  )
  and coalesce(
    (select exists (select 1 from ancestors where ancestor_id = public.current_profile_id())),
    false
  );
$function$;

-- ───────── س٢ ─────────
insert into public.app_config (key, value, default_value, kind, min_value, max_value, category, label_ar, help_ar, rules, is_public, sort)
values
  ('self_child_daily_limit', '5'::jsonb, '5'::jsonb, 'int', 0, 30, 'tree', 'أقصى عدد أبناء يضيفهم العضو بنفسه في اليوم',
   'العضو يضيف ابنه مباشرة بلا موافقة ويصل إشعار للمالك والمدير. ٠ = يعود الابن طلباً للإدارة.',
   '{}'::jsonb, false, 63)
on conflict (key) do nothing;

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
      -- ابن العضو المباشر: فقط من add_family_child (العلم محلي للمعاملة)، ابنه هو، عضو بلا امتيازات
      if not (coalesce(current_setting('family.self_child', true), '') = 'on'
              and caller_role = 'member' and new.status = 'active' and new.role = 'member'
              and new.father_id = me and new.id <> me) then
        raise exception 'approval_required' using errcode = '42501';
      end if;
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

create or replace function public.add_family_child(p_parent_id uuid, p_name text, p_gender text DEFAULT 'male'::text, p_birth date DEFAULT NULL::date, p_deceased boolean DEFAULT false, p_death date DEFAULT NULL::date, p_sort integer DEFAULT 0, p_parent_full_name text DEFAULT ''::text)
 returns uuid
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  g text := lower(coalesce(p_gender, 'male'));
  new_id uuid := gen_random_uuid();
  nm text := trim(coalesce(p_name, ''));
  chained text := case
    when coalesce(trim(p_parent_full_name), '') = '' then nm
    else nm || ' ' || trim(p_parent_full_name)
  end;
  my_role text := coalesce(public.current_user_role(), '');
  me uuid := public.current_profile_id();
  staff boolean := my_role in ('owner', 'admin', 'monitor');
  v_limit int;
  v_today int;
  me_first text;
begin
  if not (staff or (p_parent_id = any (array[auth.uid(), me]) and my_role in ('member', 'supervisor'))) then
    raise exception 'not_authorized';
  end if;
  if nm = '' then
    raise exception 'name_required';
  end if;

  if g = 'female' then
    insert into public.women_members(
      id, first_name, full_name, parent_id, gender,
      is_deceased, birth_date, death_date, sort_order)
    values (
      new_id, nm, chained, p_parent_id, 'female',
      coalesce(p_deceased, false), p_birth,
      case when p_deceased then p_death else null end,
      coalesce(p_sort, 0));
  else
    if not staff then
      -- ابن العضو لنفسه: مباشر بحدّ يومي (٠ = مغلق → التطبيق يرجع للطلب)
      if p_parent_id is distinct from me then
        raise exception 'not_authorized';
      end if;
      v_limit := coalesce((select (c.value #>> '{}')::int from public.app_config c where c.key = 'self_child_daily_limit'), 5);
      select count(*) into v_today from public.profiles p
       where p.father_id = me and p.created_at >= date_trunc('day', now() at time zone 'Asia/Kuwait') at time zone 'Asia/Kuwait';
      if v_limit <= 0 or v_today >= v_limit then
        raise exception 'وصلت حد الإضافة اليومي — أكمل غداً أو اطلب من الإدارة'
          using errcode = '42501', hint = 'daily_limit';
      end if;
      perform set_config('family.self_child', 'on', true);
    end if;
    insert into public.profiles(
      id, first_name, full_name, father_id, gender, status, role,
      is_deceased, birth_date, death_date, sort_order,
      is_phone_verified, is_hr_member)
    values (
      new_id, nm, chained, p_parent_id, 'male', 'active', 'member',
      coalesce(p_deceased, false), p_birth,
      case when p_deceased then p_death else null end,
      coalesce(p_sort, 0), false, false);
    -- إدراج profiles يُنشئ نسخة ذكر في شجرة النساء (نفس id) عبر المزامنة.
    if not staff then
      perform set_config('family.self_child', '', true);
      me_first := coalesce((select nullif(btrim(p.first_name), '') from public.profiles p where p.id = me), 'عضو');
      insert into public.notifications (target_member_id, title, body, kind, created_by, subject_member_id)
      select p.id, 'إضافة ابن للشجرة', me_first || ' أضاف ابنه «' || nm || '» للشجرة',
             'admin_edit_child_add', me, new_id
        from public.profiles p
       where p.role in ('owner', 'admin')
         and p.status = 'active'
         and p.id <> me;
    end if;
  end if;
  return new_id;
end;
$function$;

-- ───────── س٣/٤ ─────────
create or replace function public.set_self_relative_mother(p_child_id uuid, p_mother_id uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  me     uuid := public.my_active_women_node();
  my_dad uuid;
  c      public.women_members%rowtype;
  owner_node uuid;   -- أبو الطفل: أنا (أبنائي) أو أبي (أخواتي)
begin
  if me is null then
    raise exception 'حسابك غير مفعّل أو بلا عقدة في الشجرة' using errcode = '42501', hint = 'no_node';
  end if;
  select * into c from public.women_members where id = p_child_id for update;
  if not found or c.id = me then
    raise exception 'هذا ليس من أقاربك' using errcode = '42501', hint = 'not_your_relative';
  end if;
  select parent_id into my_dad from public.women_members where id = me;
  if c.parent_id = me then
    owner_node := me;
  elsif my_dad is not null and c.parent_id = my_dad and c.gender = 'female' then
    owner_node := my_dad;
  else
    raise exception 'هذا ليس من أقاربك' using errcode = '42501', hint = 'not_your_relative';
  end if;
  if c.linked_user_id is not null
     or exists (select 1 from auth.users u where u.id = c.id or (u.raw_app_meta_data ->> 'profile_id') = c.id::text) then
    raise exception 'له حساب دخول — تربطه الإدارة' using errcode = '42501', hint = 'has_account';
  end if;
  if p_mother_id is not null and not exists (
       select 1 from public.women_members w
        where w.id = p_mother_id and w.gender = 'female' and w.husband_id = owner_node) then
    raise exception 'الأم يجب أن تكون زوجة الأب' using errcode = '42501', hint = 'not_wife_of_father';
  end if;
  update public.women_members set mother_id = p_mother_id where id = c.id;
  -- profiles.mother_id يشير إلى profiles: الأم من خارج الملفات تبقى في women_members فقط
  update public.profiles
     set mother_id = case when exists (select 1 from public.profiles m where m.id = p_mother_id) then p_mother_id end
   where id = c.id
     and mother_id is distinct from (case when exists (select 1 from public.profiles m where m.id = p_mother_id) then p_mother_id end);
  return jsonb_build_object('id', c.id, 'mother_id', p_mother_id);
end;
$function$;
revoke all on function public.set_self_relative_mother(uuid, uuid) from public, anon;
grant execute on function public.set_self_relative_mother(uuid, uuid) to authenticated;

-- ───────── س٥ ─────────
create or replace function public.add_self_mother(p_name text)
 returns uuid
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare me uuid := public.my_active_women_node(); fid uuid; cur uuid; nid uuid := gen_random_uuid(); nm text := trim(coalesce(p_name,''));
begin
  if me is null then raise exception 'no_node'; end if;
  if nm = '' then raise exception 'name_required'; end if;
  select parent_id, mother_id into fid, cur from public.women_members where id = me;
  if fid is null then raise exception 'no_father'; end if;
  if cur is not null then
    raise exception 'لك أم مسجّلة — غيّرها من «اختيار الأم»' using errcode = '42501', hint = 'mother_exists';
  end if;
  insert into public.women_members(id, first_name, full_name, husband_id, gender, sort_order)
    values (nid, nm, nm, fid, 'female', 0);
  update public.women_members set mother_id = nid where id = me;
  return nid;
end; $function$;

-- ───────── س٧ ─────────
revoke execute on function public.set_self_wife(uuid) from public, anon, authenticated;
