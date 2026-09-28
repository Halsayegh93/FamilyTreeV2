-- صلاحية المشرف + قفل الوظائف + منع نقل الملفات المربوطة — 2026-09-28 (طلب المالك)
--
-- 1) merge_member_into_tree: الدمج من «الشجرة والأعضاء» — المالك/المدير/المراقب فقط
--    (كان يسمح للمشرف). الهوية من current_profile_id() والحالة مفعّلة، ولا يُمس المالك.
-- 2) قفل وظائف داخلية كانت متاحة لأي أحد (حتى بدون دخول) — تُستدعى فقط من
--    التريغرات (SECURITY DEFINER) أو المهمة المجدولة (postgres):
--    dispatch_due_scheduled_notifications، is_in_supervisor_branch_test،
--    mirror_profile_wife_to_women، notification_push_allowed.
-- 3) adopt_tree_profile: لا ينقل ملفاً مربوطاً أصلاً بحساب دخول متحقَّق برقمه،
--    ولا ينقل ملف المالك تلقائياً — حماية ثانية فوق إصلاح مطابقة الأرقام
--    (20260928100000) حتى لا يتكرر نقل حساب المالك.

begin;

-- ─── 1) الدمج: المالك/المدير/المراقب فقط ───────────────────────────
create or replace function public.merge_member_into_tree(p_new_member_id uuid, p_tree_member_id uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_new    public.profiles%rowtype;
  v_tree   public.profiles%rowtype;
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

  -- ─── 4) نقل الإشعارات ─────────────────────────────────────────
  update public.notifications
    set target_member_id = p_new_member_id
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

  -- ─── 8) حذف السجل القديم (cascade يعتني بالباقي) ───────────────
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

revoke execute on function public.merge_member_into_tree(uuid, uuid) from public, anon;
grant execute on function public.merge_member_into_tree(uuid, uuid) to authenticated, service_role;

-- ─── 2) قفل الوظائف الداخلية ────────────────────────────────────────
revoke execute on function public.dispatch_due_scheduled_notifications() from public, anon, authenticated;
revoke execute on function public.is_in_supervisor_branch_test(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.mirror_profile_wife_to_women(uuid) from public, anon, authenticated;
revoke execute on function public.notification_push_allowed(uuid, text, uuid) from public, anon, authenticated;
grant execute on function public.dispatch_due_scheduled_notifications() to service_role;
grant execute on function public.is_in_supervisor_branch_test(uuid, uuid) to service_role;
grant execute on function public.mirror_profile_wife_to_women(uuid) to service_role;
grant execute on function public.notification_push_allowed(uuid, text, uuid) to service_role;

-- ─── 3) adopt_tree_profile: لا نقل لملف مربوط بصاحبه ولا لملف المالك ──
create or replace function public.adopt_tree_profile(p_auth_uid uuid, p_tree_id uuid)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_tree public.profiles%rowtype;
  v_stub public.profiles%rowtype;
  c      record;
begin
  if p_auth_uid is null or p_tree_id is null or p_auth_uid = p_tree_id then
    return;
  end if;

  select * into v_tree from public.profiles where id = p_tree_id for update;
  if v_tree.id is null then
    return;
  end if;

  -- حماية: ملف المالك لا يُنقل تلقائياً أبداً
  if v_tree.role = 'owner' then
    raise warning '[ADOPT] رُفض نقل ملف المالك % إلى %', p_tree_id, p_auth_uid;
    return;
  end if;

  -- حماية: الملف مربوط أصلاً بحساب دخول متحقَّق من رقمه (صاحبه الفعلي) → لا يُسحب منه
  if exists (
    select 1 from auth.users u
    where u.id = p_tree_id
      and u.phone_confirmed_at is not null
      and public.phones_match_suffix(u.phone, v_tree.phone_number)
  ) then
    raise warning '[ADOPT] رُفض: الملف % مربوط بحساب دخول متحقَّق', p_tree_id;
    return;
  end if;

  select * into v_stub from public.profiles where id = p_auth_uid for update;

  -- 2.1) تحرير الرقم من صف الشجرة أولاً (unique index على phone_number)
  update public.profiles set phone_number = null where id = p_tree_id;

  if v_stub.id is null then
    -- 2.2أ) لا يوجد صف للحساب → استنساخ صف الشجرة كاملاً بمعرف الحساب
    insert into public.profiles
    select (jsonb_populate_record(
              null::public.profiles,
              to_jsonb(v_tree) || jsonb_build_object('id', p_auth_uid)
           )).*;
  else
    -- 2.2ب) يوجد صف ناقص → ننقل إليه هوية الشجرة (نفس حقول merge_member_into_tree
    -- مع الأعمدة الأحدث: gender/mother_id/husband_id/sons_ids/الصور)
    update public.profiles set
      full_name           = v_tree.full_name,
      first_name          = v_tree.first_name,
      phone_number        = coalesce(v_tree.phone_number, v_stub.phone_number),
      role                = case when coalesce(v_stub.role, 'pending') in ('pending', 'member')
                                 then coalesce(v_tree.role, 'member') else v_stub.role end,
      status              = coalesce(v_tree.status, 'active'),
      father_id           = v_tree.father_id,
      mother_id           = v_tree.mother_id,
      husband_id          = v_tree.husband_id,
      sons_ids            = v_tree.sons_ids,
      sort_order          = v_tree.sort_order,
      is_deceased         = coalesce(v_tree.is_deceased, false),
      is_married          = coalesce(v_tree.is_married, false),
      is_hidden_from_tree = coalesce(v_tree.is_hidden_from_tree, false),
      is_phone_hidden     = coalesce(v_tree.is_phone_hidden, false),
      birth_date          = coalesce(v_tree.birth_date, v_stub.birth_date),
      death_date          = v_tree.death_date,
      gender              = coalesce(v_tree.gender, v_stub.gender),
      bio                 = coalesce(v_tree.bio, v_stub.bio),
      bio_json            = coalesce(v_tree.bio_json, v_stub.bio_json),
      avatar_url          = coalesce(nullif(v_tree.avatar_url, ''), v_stub.avatar_url),
      cover_url           = coalesce(nullif(v_tree.cover_url,  ''), v_stub.cover_url),
      photo_url           = coalesce(nullif(v_tree.photo_url,  ''), v_stub.photo_url),
      created_at          = least(coalesce(v_tree.created_at, v_stub.created_at),
                                  coalesce(v_stub.created_at, v_tree.created_at))
    where id = p_auth_uid;
  end if;

  -- 2.3) إعادة توجيه كل الأعمدة المُشيرة إلى profiles(id) — ديناميكياً حتى
  -- تشمل الجداول الحالية والمستقبلية (news/notifications/device_tokens/
  -- admin_requests/diwaniyas/women_members/... إلخ). أي جدول يفشل بقيد
  -- فريد (نادر) يُتخطى بدل إفشال الدخول كاملاً.
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
        using p_auth_uid, p_tree_id;
    exception when others then
      raise warning '[ADOPT] تخطي إعادة توجيه %.%: %', c.tbl, c.col, sqlerrm;
    end;
  end loop;

  -- 2.4) مصفوفة الأبناء sons_ids (لا يغطيها فحص FK)
  update public.profiles
     set sons_ids = array_replace(sons_ids, p_tree_id, p_auth_uid)
   where sons_ids is not null
     and p_tree_id = any(sons_ids);

  -- 2.5) حذف صف الشجرة القديم (كل المراجع تحوّلت)
  delete from public.profiles where id = p_tree_id;
end;
$function$;

revoke execute on function public.adopt_tree_profile(uuid, uuid) from public, anon, authenticated;

commit;
