-- تراجع عن 20261001150000_protect_family_links.sql
-- يعيد الروابط الست إلى ON DELETE SET NULL، ويحذف الحراس والدالة المساعدة، ويعيد
-- adopt_tree_profile و merge_member_into_tree و women_auto_merge_wife كما كانت على السيرفر
-- يوم ٢٠٢٦-١٠-٠١ قبل التطبيق.
-- سجلّ family_link_history يبقى للاطلاع (لحذفه: drop table public.family_link_history;).
-- ⚠️ بعد التراجع يعود الخطر الأصلي: حذف/نقل ملف يفرّغ روابط الزوجة والبنات بصمت.

drop trigger if exists trg_zzz_family_links_guard on public.profiles;
drop trigger if exists trg_zzz_family_links_guard on public.women_members;
drop trigger if exists trg_family_links_protect_delete on public.profiles;
drop trigger if exists trg_family_links_protect_delete on public.women_members;

alter table public.profiles
  drop constraint profiles_father_id_fkey,
  add  constraint profiles_father_id_fkey
       foreign key (father_id) references public.profiles(id) on delete set null,
  drop constraint profiles_mother_id_fkey,
  add  constraint profiles_mother_id_fkey
       foreign key (mother_id) references public.profiles(id) on delete set null,
  drop constraint profiles_husband_id_fkey,
  add  constraint profiles_husband_id_fkey
       foreign key (husband_id) references public.profiles(id) on delete set null;

alter table public.women_members
  drop constraint women_members_parent_id_fkey,
  add  constraint women_members_parent_id_fkey
       foreign key (parent_id) references public.women_members(id) on delete set null,
  drop constraint women_members_mother_id_fkey,
  add  constraint women_members_mother_id_fkey
       foreign key (mother_id) references public.women_members(id) on delete set null,
  drop constraint women_members_husband_id_fkey,
  add  constraint women_members_husband_id_fkey
       foreign key (husband_id) references public.women_members(id) on delete set null;

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

  if v_tree.role in ('owner', 'admin', 'monitor', 'supervisor') then
    raise warning '[ADOPT] رُفض نقل ملف الإدارة % (%) إلى %', p_tree_id, v_tree.role, p_auth_uid;
    return;
  end if;

  if exists (select 1 from auth.users u where u.id = p_tree_id)
     or exists (
       select 1 from auth.users u
       where u.id <> p_auth_uid
         and coalesce(u.raw_app_meta_data->>'profile_id', '') = p_tree_id::text
     ) then
    raise warning '[ADOPT] رُفض: الملف % مربوط بحساب دخول — لا يُنقل آلياً', p_tree_id;
    return;
  end if;

  select * into v_stub from public.profiles where id = p_auth_uid for update;

  update public.profiles set phone_number = null where id = p_tree_id;

  if v_stub.id is null then
    insert into public.profiles
    select (jsonb_populate_record(
              null::public.profiles,
              to_jsonb(v_tree) || jsonb_build_object('id', p_auth_uid)
           )).*;
  else
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

  update public.profiles
     set sons_ids = array_replace(sons_ids, p_tree_id, p_auth_uid)
   where sons_ids is not null
     and p_tree_id = any(sons_ids);

  delete from public.profiles where id = p_tree_id;
end;
$function$;

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

create or replace function public.women_auto_merge_wife()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  dup_ids uuid[];
begin
  if new.husband_id is null or lower(coalesce(new.gender, '')) <> 'female' then
    return new;
  end if;

  -- أمّهات منفصلات (بلا زوج) بنفس الاسم الأول وهنّ أمّهات لأبناء هذا الزوج.
  dup_ids := array(
    select distinct m.id
    from public.women_members m
    join public.women_members c
      on c.mother_id = m.id and c.parent_id = new.husband_id
    where m.husband_id is null
      and m.id <> new.id
      and m.first_name = new.first_name
  );

  if array_length(dup_ids, 1) is null then
    return new;
  end if;

  -- انقل أمومة أبناء هذا الزوج إلى الزوجة الجديدة.
  update public.women_members
     set mother_id = new.id
   where parent_id = new.husband_id
     and mother_id = any(dup_ids);

  -- احذف السجلات المنفصلة المكررة.
  delete from public.women_members where id = any(dup_ids);

  return new;
end;
$function$;

drop function if exists public.repoint_women_node(uuid, uuid);
drop function if exists public.trg_family_links_guard();
drop function if exists public.trg_family_links_protect_delete();
