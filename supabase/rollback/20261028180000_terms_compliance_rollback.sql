-- تراجع 20261028180000_terms_compliance (الدوال المعدّلة بنصّها السابق حرفياً)
CREATE OR REPLACE FUNCTION public.guard_admin_request_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me          uuid := auth.uid();
  my_profile  uuid := public.current_profile_id();
  caller_role text;
  d           jsonb;
  act         text;
  tgt         text;
  par         text;
  member_name text;
  child       record;
  uuid_re     constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
begin
  -- السيرفر وصيانة SQL (مثل حارس الأدوار prevent_role_self_promotion).
  if auth.role() = 'service_role'
     or (auth.role() is null and session_user in ('postgres','supabase_admin','supabase_auth_admin')) then
    return new;
  end if;
  -- بلا دخول: سياسات الجدول ترفضه.
  if me is null then
    return new;
  end if;
  caller_role := coalesce(public.current_user_role(), 'pending');
  if caller_role in ('owner','admin','monitor','supervisor') then
    return new;
  end if;

  new.status      := 'pending';
  new.admin_reply := null;
  new.replied_at  := null;
  new.replied_by  := null;
  new.created_at  := now();

  if new.request_type is null or new.request_type not in (
       'link_request','contact_message','tree_edit','name_change','family_change',
       'phone_change','child_add','news_report','content_report') then
    raise exception 'admin_request_type_not_allowed' using errcode = '42501';
  end if;
  if new.requester_id is null
     or (new.requester_id is distinct from me and new.requester_id is distinct from my_profile) then
    raise exception 'admin_request_requester_not_self' using errcode = '42501';
  end if;
  if new.member_id is null then
    raise exception 'admin_request_member_required' using errcode = '42501';
  end if;
  if new.request_type not in ('link_request','contact_message') and not public.is_approved_member() then
    raise exception 'admin_request_requires_active_member' using errcode = '42501';
  end if;
  if new.request_type <> 'tree_edit' and new.member_id <> new.requester_id then
    raise exception 'admin_request_not_about_self' using errcode = '42501';
  end if;

  -- رفض «إضافة ابن» يحذف الملف new_value: ابن جديد لمقدّم الطلب فقط.
  if new.request_type = 'child_add' then
    if coalesce(new.new_value, '') !~ uuid_re then
      raise exception 'admin_request_child_invalid' using errcode = '42501';
    end if;
    select p.id, p.father_id, p.created_at, p.role into child
    from public.profiles p where p.id = new.new_value::uuid;
    if not found
       or child.father_id is distinct from new.member_id
       or child.created_at is null or child.created_at < now() - interval '1 hour'
       or coalesce(child.role, '') in ('owner','admin','monitor','supervisor')
       or exists (select 1 from auth.users u where u.id = child.id)
       or exists (select 1 from public.admin_requests r
                  where r.request_type = 'child_add' and lower(r.new_value) = lower(new.new_value)) then
      raise exception 'admin_request_child_invalid' using errcode = '42501';
    end if;
  end if;

  -- قبول أي بلاغ يحذف الخبر new_value: البلاغ عن محتوى لا يشير إلى خبر.
  if new.request_type = 'content_report' and coalesce(new.new_value, '') ~ uuid_re
     and exists (select 1 from public.news n where n.id = new.new_value::uuid) then
    raise exception 'admin_request_report_targets_news' using errcode = '42501';
  end if;

  if new.request_type = 'tree_edit' then
    begin
      d := new.details::jsonb;
    exception when others then
      d := null;
    end;
    if d is null or jsonb_typeof(d) <> 'object' then
      raise exception 'admin_request_tree_edit_invalid' using errcode = '42501';
    end if;
    act := d->>'action';
    -- القديمة (قبل ٢٠٢٦-٠٥-١١) بأسماء عربية: إضافة / تعديل اسم / حذف.
    if act is null or act not in ('add','edit_name','edit_phone','edit_birth','deceased',
         'add_death_date','add_photo','delete','other','إضافة','تعديل اسم','حذف') then
      raise exception 'admin_request_tree_edit_invalid' using errcode = '42501';
    end if;
    new.new_value := act;

    -- الموافقة تكتب على targetMemberId (والإضافة تحت parentMemberId): لازم = member_id.
    tgt := d->>'targetMemberId';
    par := d->>'parentMemberId';
    if (tgt is not null and (tgt !~ uuid_re or tgt::uuid <> new.member_id))
       or (par is not null and (par !~ uuid_re or par::uuid <> new.member_id))
       or (act in ('add','إضافة') and par is null)
       or (act not in ('add','إضافة') and tgt is null) then
      raise exception 'admin_request_tree_edit_target_mismatch' using errcode = '42501';
    end if;

    if act = 'add_photo' and coalesce(d->>'newPhotoUrl', '') !~* (
         '^https://poxyxsgvzwmnmewytsiw\.supabase\.co/storage/v1/object/public/avatars/photo_suggestion_'
         || new.requester_id::text || '_[0-9a-f-]{36}\.jpg$') then
      raise exception 'admin_request_tree_edit_photo_invalid' using errcode = '42501';
    end if;

    -- «طلب آخر» يأتي فقط من تعديل العضو لملفه بعد تجاوز الحد.
    if act = 'other' and (coalesce(d->>'reason', '') not in ('profile_marital','profile_bio','profile_phone_hidden')
                          or new.member_id <> new.requester_id) then
      raise exception 'admin_request_tree_edit_invalid' using errcode = '42501';
    end if;

    -- «تعديل مباشر من الإدارة» لا يكتبه عضو، والأسماء من السيرفر.
    d := d - 'isAdminDirectEdit';
    select p.full_name into member_name from public.profiles p where p.id = new.member_id;
    if tgt is not null then
      d := case when member_name is null then d - 'targetMemberName'
                else jsonb_set(d, '{targetMemberName}', to_jsonb(member_name)) end;
    end if;
    if par is not null then
      d := case when member_name is null then d - 'parentMemberName'
                else jsonb_set(d, '{parentMemberName}', to_jsonb(member_name)) end;
    end if;
    new.details := d::text;
  end if;

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.merge_member_into_tree(p_new_member_id uuid, p_tree_member_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_new    public.profiles%rowtype;
  v_tree   public.profiles%rowtype;
  c        record;
begin
  -- ─── حماية: الدمج من مجال «الشجرة والأعضاء» — المالك/المدير/المراقب ───
  -- (المشرف مجاله المحتوى والبلاغات فقط — راجع Core/RoleGuides.swift)
  if not exists (
    select 1 from public.profiles
    where id = public.current_profile_id()
      and role in ('owner','admin','monitor')
      and status = 'active'
  ) then
    return jsonb_build_object('success', false, 'message', 'غير مصرّح لك بهذا الإجراء');
  end if;

  -- ─── حماية: لا يمكن الدمج مع النفس ───────────────────────────
  if p_new_member_id = p_tree_member_id then
    return jsonb_build_object('success', false, 'message', 'لا يمكن دمج العضو مع نفسه');
  end if;

  -- ─── 0) تحميل السجلين مع قفل للتعديل ────────────────────────
  select * into v_new  from public.profiles where id = p_new_member_id  for update;
  select * into v_tree from public.profiles where id = p_tree_member_id for update;

  if v_new.id is null then
    return jsonb_build_object('success', false, 'message', 'سجل العضو الجديد غير موجود');
  end if;
  if v_tree.id is null then
    return jsonb_build_object('success', false, 'message', 'سجل عضو الشجرة غير موجود');
  end if;

  -- ─── حماية: ملف المالك لا يُدمج ولا يُدمج فيه ──────────────────
  if v_new.role = 'owner' or v_tree.role = 'owner' then
    return jsonb_build_object('success', false, 'message', 'لا يمكن دمج حساب المالك');
  end if;

  -- ─── حماية (فحص الثغرات ٢٠٢٦-١٠-٠٤): نفس حراس adopt_tree_profile ─────────────
  -- سجل الشجرة يُحذف بعد الدمج — فلا يكون ملف أحد الإدارة ولا ملفاً له حساب دخول
  -- (كان اختيار ابن العم الخطأ يحذف ملف عضو شغّال وتصل لأجهزته إشعارات غيره).
  if v_tree.role in ('admin', 'monitor', 'supervisor') then
    return jsonb_build_object('success', false, 'message', 'لا يمكن الدمج في ملف أحد أعضاء الإدارة');
  end if;
  if exists (select 1 from auth.users u
             where u.id = p_tree_member_id
                or coalesce(u.raw_app_meta_data->>'profile_id', '') = p_tree_member_id::text) then
    return jsonb_build_object('success', false, 'message', 'سجل الشجرة مربوط بحساب دخول شغّال — لا يمكن الدمج فيه');
  end if;
  -- والسجل الجديد يصير «عضو» بعد الدمج — فلا يُدمج حساب أحد الإدارة (كان ينزّل دوره)
  if v_new.role in ('admin', 'monitor', 'supervisor') then
    return jsonb_build_object('success', false, 'message', 'لا يمكن دمج حساب أحد أعضاء الإدارة');
  end if;

  -- ─── 1) تحديث السجل الجديد ببيانات الشجرة ─────────────────────
  update public.profiles set
    role               = 'member',
    status             = 'active',
    is_hidden_from_tree = false,
    full_name          = v_tree.full_name,
    first_name         = v_tree.first_name,
    father_id          = v_tree.father_id,
    sort_order         = v_tree.sort_order,
    is_deceased        = coalesce(v_tree.is_deceased, false),
    is_married         = coalesce(v_tree.is_married, false),
    birth_date         = coalesce(v_tree.birth_date, v_new.birth_date),
    death_date         = v_tree.death_date,
    gender             = coalesce(v_tree.gender, v_new.gender),
    bio                = coalesce(v_tree.bio, v_new.bio),
    avatar_url         = coalesce(nullif(v_tree.avatar_url,''), v_new.avatar_url),
    cover_url          = coalesce(nullif(v_tree.cover_url,''),  v_new.cover_url),
    photo_url          = coalesce(nullif(v_tree.photo_url,''),  v_new.photo_url),
    -- العائلة المختارة عند التسجيل، وإلا عائلة سجل الشجرة (طلب المالك)
    family_name        = coalesce(nullif(trim(v_new.family_name), ''), v_tree.family_name)
  where id = p_new_member_id;

  -- ─── 2) إعادة ربط الأبناء ─────────────────────────────────────
  update public.profiles
    set father_id = p_new_member_id
  where father_id = p_tree_member_id;

  -- ─── 3) نقل صور المعرض ────────────────────────────────────────
  update public.member_gallery_photos
    set member_id = p_new_member_id
  where member_id = p_tree_member_id;

  -- ─── 4) إشعارات سجل الشجرة القديمة لا تنتقل (٢٠٢٦-١٠-٠٤، طلب المالك) ───
  -- الإشعارات تبدأ مع العضو من دخوله؛ إشعارات سجله الجديد نفسه تبقى كما هي.
  delete from public.notifications
  where target_member_id = p_tree_member_id;

  -- ─── 5) قبول طلبات الانضمام المعلقة للعضو الجديد ──────────────
  update public.admin_requests
    set status = 'approved'
  where member_id = p_new_member_id
    and request_type in ('join_request', 'link_request')
    and status = 'pending';

  -- ─── 6) حذف طلبات العضو القديم ────────────────────────────────
  delete from public.admin_requests
  where member_id    = p_tree_member_id
     or requester_id = p_tree_member_id;

  -- ─── 7) نقل الأجهزة ───────────────────────────────────────────
  update public.device_tokens
    set member_id = p_new_member_id
  where member_id = p_tree_member_id;

  -- ─── 7.٥) جديد (٢٠٢٦-١٠-٠١): كل ما يشير للسجل القديم ينتقل قبل حذفه ─────────
  -- عقدة شجرة النساء (الزوجة، البنات)، الأم/الزوج، وأي مرجع آخر — كان الحذف
  -- يفرّغها بصمت (ON DELETE SET NULL) أو يحذفها (CASCADE).
  perform public.repoint_women_node(p_tree_member_id, p_new_member_id);

  for c in
    select con.conrelid::regclass as tbl, att.attname as col
      from pg_constraint con
      join pg_attribute att
        on att.attrelid = con.conrelid and att.attnum = con.conkey[1]
     where con.contype = 'f'
       and con.confrelid = 'public.profiles'::regclass
       and array_length(con.conkey, 1) = 1
  loop
    begin
      execute format('update %s set %I = $1 where %I = $2', c.tbl, c.col, c.col)
        using p_new_member_id, p_tree_member_id;
    exception when others then
      raise warning '[MERGE] تخطي إعادة توجيه %.%: %', c.tbl, c.col, sqlerrm;
    end;
  end loop;

  update public.profiles
     set sons_ids = array_replace(sons_ids, p_tree_member_id, p_new_member_id)
   where sons_ids is not null
     and p_tree_member_id = any(sons_ids);

  -- ─── 8) حذف السجل القديم (الحارس يرفض إن بقي أحد من العائلة مربوطاً به) ─────
  delete from public.profiles where id = p_tree_member_id;

  -- ─── 9) العائلة المختارة تسري على الأبناء المنقولين وذرّيتهم (بعد حذف السجل القديم) ─
  if nullif(trim(v_new.family_name), '') is not null then
    with recursive line as (
      select id from public.profiles where father_id = p_new_member_id
      union all
      select p.id from public.profiles p join line l on p.father_id = l.id
    )
    -- updated_by قد يشير لعضو محذوف (بيانات قديمة) — يُفرَّغ هنا وإلا فشل التحديث الثاني
    update public.profiles
       set family_name = trim(v_new.family_name),
           updated_by = case when exists (select 1 from public.profiles q where q.id = profiles.updated_by)
                             then updated_by end
     where id in (select id from line);
  end if;


  return jsonb_build_object(
    'success', true,
    'message', format('تم دمج %s بنجاح وتفعيل حسابه', v_tree.full_name),
    'merged_name', v_tree.full_name
  );

exception
  when others then
    -- أي خطأ يُلغي كل العمليات تلقائياً (PostgreSQL transaction rollback)
    return jsonb_build_object(
      'success', false,
      'message', format('فشل الدمج: %s', sqlerrm)
    );
end;
$function$;

CREATE OR REPLACE FUNCTION public.trg_profiles_protect_sensitive_columns()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

create or replace view public.members_masked as
SELECT id,
    first_name,
    full_name,
        CASE
            WHEN COALESCE(is_phone_hidden, false) = false OR id = auth.uid() OR is_team(auth.uid()) THEN phone_number
            ELSE NULL::text
        END AS phone_number,
    birth_date,
    death_date,
    is_deceased,
    role,
    father_id,
    photo_url,
    is_phone_hidden,
    is_hidden_from_tree,
    sort_order,
    bio_json,
    sons_ids,
    status,
    created_at,
    is_married,
    avatar_url,
    bio,
    is_approved,
    is_admin,
    is_phone_verified,
    is_birth_date_hidden,
    cover_url,
    badge_enabled,
    gender,
    updated_by,
    updated_at,
    is_hr_member,
    hr_status,
    last_seen_at,
    registration_platform,
    username,
    last_active_at,
    current_screen,
    current_screen_source,
        CASE
            WHEN id = auth.uid() OR is_team(auth.uid()) THEN email
            ELSE NULL::text
        END AS email,
    mother_id,
    husband_id,
    terms_accepted_at,
    family_name,
    death_date_unknown,
    avatar_unavailable
   FROM profiles p
  WHERE auth.uid() IS NOT NULL AND (id = auth.uid() OR is_approved_member());

drop trigger if exists trg_profiles_age_rules on public.profiles;
drop function if exists public.trg_profiles_age_rules();
drop function if exists public.set_member_suspension(uuid,boolean,text);
drop function if exists public.my_suspension();
drop function if exists public.decide_privacy_request(uuid,boolean,text);
drop function if exists public.request_privacy_change(text,text);
drop function if exists public.decide_guardian_consent(uuid,boolean);
drop function if exists public.my_guardian_requests();
drop function if exists public.request_guardian_consent(uuid,uuid);
drop function if exists public.has_guardian_consent(uuid,uuid);
drop table if exists public.guardian_consents;
drop function if exists public.reject_account_deletion(uuid,text);
drop function if exists public.cancel_account_deletion_request();
drop function if exists public.request_account_deletion();
drop function if exists public.my_account_deletion_request();
drop function if exists public.account_auth_id(uuid);
-- الأعمدة is_photo_hidden و frozen_reason والدالة age_years تبقى (إضافية بلا ضرر).
