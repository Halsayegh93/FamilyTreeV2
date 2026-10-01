-- حماية روابط العائلة لكل الأعضاء (طلب المالك ٢٠٢٦-١٠-٠١)
-- «حافظ على هذا الربط واحميه وحتى الاعضاء في التطبيق لا تفصل عنهم الربط نهائياً»
--
-- ما حدث: زوجة المالك وبناته انفصلن عنه ٣ مرات (٢٤/٩ و٢٧/٩ و٢٨/٩) بلا إجراء من أحد.
-- السبب الجذري: نقل الملف لمعرّف جديد — adopt_tree_profile (أول دخول بالرقم) و
-- merge_member_into_tree («ربط بالشجرة») — ينقل ما يشير إلى profiles فقط، ثم يحذف الملف
-- القديم ← sync_profile_delete_to_women يحذف عقدته في شجرة النساء ← ON DELETE SET NULL
-- يفرّغ husband_id / parent_id للزوجة والبنات بصمت. يصيب أي عضو، لا المالك فقط.
--
-- الحماية:
--   ١) لا حذف يفصل أحداً: روابط العائلة الست NO ACTION بدل SET NULL، وحارس قبل الحذف
--      يرفض حذف أي شخص ما زال له أبناء/بنات/زوجة مرتبطون — برسالة عربية واضحة.
--   ٢) نقل الملف ينقل كل روابطه: عقدة شجرة النساء وكل من يشير لها (repoint_women_node)،
--      و merge صار ينقل كل ما يشير للملف القديم (كان الأبناء فقط).
--   ٣) لا تفريغ آلي: أي عملية بلا مستخدم (دالة سيرفر، مفتاح الخدمة، صيانة SQL) تحاول تفريغ
--      رابط عائلة ← تبقى القيمة القديمة وتُسجَّل المحاولة. الفصل اليدوي المقصود من التطبيق
--      أو الموقع (عضو يزيل زوجته، مدير يصحّح أباً) يبقى كما هو ويُسجَّل.
--   ٤) family_link_history: كل تغيير في رابط (قبل/بعد/من/متى) — للاسترجاع. للمالك والمدير.
--   ٥) women_auto_merge_wife: لا يحذف سجلاً مكرراً ما زال له تابعون.
--
-- حذف الحساب (finalize_account_deletion) لا يتأثر: يُخفي البيانات ويُبقي السجل وروابطه.
-- صيانة مقصودة فقط: select set_config('family.allow_unlink', 'on', true); في نفس المعاملة.
-- التراجع: supabase/rollback/20261001150000_protect_family_links_rollback.sql

-- ─── ٤) سجلّ تغييرات الروابط (أولاً — الحراس تكتب فيه) ──────────────────────────
create table if not exists public.family_link_history (
  id          bigserial   primary key,
  changed_at  timestamptz not null default now(),
  tbl         text        not null,               -- profiles | women_members
  member_id   uuid        not null,
  member_name text,
  col         text        not null,               -- father_id | parent_id | mother_id | husband_id
  old_value   uuid,
  new_value   uuid,
  actor       uuid,                               -- auth.uid() — null = عملية آلية
  db_user     text        not null default session_user,
  blocked     boolean     not null default false  -- true = محاولة تفريغ آلية مُنعت
);
comment on table public.family_link_history is
  'كل تغيير في روابط العائلة (الأب/الأم/الزوج) قبل وبعد — للاسترجاع. blocked = محاولة تفريغ آلية مُنعت.';
create index if not exists family_link_history_member_idx
  on public.family_link_history (member_id, changed_at desc);

alter table public.family_link_history enable row level security;
revoke all on public.family_link_history from anon, authenticated;
revoke all on sequence public.family_link_history_id_seq from anon, authenticated;
grant select on public.family_link_history to authenticated;
drop policy if exists family_link_history_admin_read on public.family_link_history;
create policy family_link_history_admin_read on public.family_link_history
  for select to authenticated
  using (public.current_user_role() in ('owner', 'admin'));

-- ─── ٣) لا تفريغ آلي لروابط العائلة + تسجيل كل تغيير ─────────────────────────────
create or replace function public.trg_family_links_guard()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_cols text[] := case tg_table_name
                     when 'profiles' then array['father_id', 'mother_id', 'husband_id']
                     else array['parent_id', 'mother_id', 'husband_id'] end;
  v_old  jsonb := to_jsonb(old);
  v_new  jsonb := to_jsonb(new);
  v_keep jsonb := '{}'::jsonb;
  -- آلي = بلا مستخدم (دالة سيرفر، مفتاح الخدمة، صيانة) ولم يُطلب الفصل صراحةً
  v_auto boolean := auth.uid() is null
                    and coalesce(current_setting('family.allow_unlink', true), '') <> 'on';
  v_name text := coalesce(nullif(v_new->>'full_name', ''), v_new->>'first_name');
  c      text;
begin
  foreach c in array v_cols loop
    continue when (v_old->>c) is not distinct from (v_new->>c);

    if v_auto and (v_new->>c) is null then
      -- لا يُفرَّغ رابط عائلة آلياً أبداً: تبقى القيمة القديمة
      v_keep := v_keep || jsonb_build_object(c, v_old->>c);
      insert into public.family_link_history
        (tbl, member_id, member_name, col, old_value, new_value, actor, blocked)
      values (tg_table_name, (v_old->>'id')::uuid, v_name, c, (v_old->>c)::uuid, null, null, true);
      raise warning '[FAMILY-LINK] مُنع تفريغ % آلياً في % (%)', c, tg_table_name, v_old->>'id';
    else
      insert into public.family_link_history
        (tbl, member_id, member_name, col, old_value, new_value, actor)
      values (tg_table_name, (v_old->>'id')::uuid, v_name, c,
              (v_old->>c)::uuid, (v_new->>c)::uuid, auth.uid());
    end if;
  end loop;

  if v_keep <> '{}'::jsonb then
    new := jsonb_populate_record(new, v_keep);
  end if;
  return new;
end;
$function$;

-- الاسم يبدأ بـ zzz ليعمل بعد كل حراس التعديل الأخرى ويرى القيم النهائية
drop trigger if exists trg_zzz_family_links_guard on public.profiles;
create trigger trg_zzz_family_links_guard
  before update of father_id, mother_id, husband_id on public.profiles
  for each row execute function public.trg_family_links_guard();

drop trigger if exists trg_zzz_family_links_guard on public.women_members;
create trigger trg_zzz_family_links_guard
  before update of parent_id, mother_id, husband_id on public.women_members
  for each row execute function public.trg_family_links_guard();

-- ─── ١) لا حذف يفصل أحداً ───────────────────────────────────────────────────────
create or replace function public.trg_family_links_protect_delete()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_old   jsonb := to_jsonb(old);
  v_id    uuid  := (v_old->>'id')::uuid;
  v_name  text  := coalesce(nullif(v_old->>'full_name', ''), v_old->>'first_name', 'العضو');
  v_count int   := 0;
begin
  if tg_table_name = 'profiles' then
    select count(*) into v_count
      from public.profiles p
     where p.id <> v_id
       and (p.father_id = v_id or p.mother_id = v_id or p.husband_id = v_id);
  end if;

  -- عقدته في شجرة النساء (نفس المعرّف) تُحذف معه — من يشير لها كان ينفصل بصمت
  v_count := v_count + (
    select count(*)
      from public.women_members w
     where w.id <> v_id
       and (w.parent_id = v_id or w.mother_id = v_id or w.husband_id = v_id));

  if v_count > 0 then
    raise exception 'لا يمكن حذف «%» — مرتبط به من العائلة: % (أبناء أو بنات أو زوجة). انقلهم أو افصلهم أولاً.',
      v_name, translate(v_count::text, '0123456789', '٠١٢٣٤٥٦٧٨٩')
      using errcode = '23503', hint = 'family_links_protected';
  end if;
  return old;
end;
$function$;

drop trigger if exists trg_family_links_protect_delete on public.profiles;
create trigger trg_family_links_protect_delete
  before delete on public.profiles
  for each row execute function public.trg_family_links_protect_delete();

drop trigger if exists trg_family_links_protect_delete on public.women_members;
create trigger trg_family_links_protect_delete
  before delete on public.women_members
  for each row execute function public.trg_family_links_protect_delete();

-- الحاجز الأخير: حتى لو تجاوز أحدٌ الحارس، قاعدة البيانات نفسها ترفض الحذف بدل التفريغ
alter table public.profiles
  drop constraint profiles_father_id_fkey,
  add  constraint profiles_father_id_fkey
       foreign key (father_id)  references public.profiles(id) on delete no action,
  drop constraint profiles_mother_id_fkey,
  add  constraint profiles_mother_id_fkey
       foreign key (mother_id)  references public.profiles(id) on delete no action,
  drop constraint profiles_husband_id_fkey,
  add  constraint profiles_husband_id_fkey
       foreign key (husband_id) references public.profiles(id) on delete no action;

alter table public.women_members
  drop constraint women_members_parent_id_fkey,
  add  constraint women_members_parent_id_fkey
       foreign key (parent_id)  references public.women_members(id) on delete no action,
  drop constraint women_members_mother_id_fkey,
  add  constraint women_members_mother_id_fkey
       foreign key (mother_id)  references public.women_members(id) on delete no action,
  drop constraint women_members_husband_id_fkey,
  add  constraint women_members_husband_id_fkey
       foreign key (husband_id) references public.women_members(id) on delete no action;

-- ─── ٢) نقل الملف ينقل كل روابطه ────────────────────────────────────────────────
-- عقدة p_old في شجرة النساء تنتقل إلى p_new مع كل من يشير لها: الزوجة، البنات، عقد
-- الأبناء، أزواج البنات من خارج العائلة، روابط الموقع — قبل حذف p_old.
create or replace function public.repoint_women_node(p_old uuid, p_new uuid)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  c record;
begin
  if p_old is null or p_new is null or p_old = p_new
     or not exists (select 1 from public.women_members where id = p_old) then
    return;
  end if;

  -- للمعرّف الجديد عقدة (المزامنة تنشئها غالباً) — وإلا نسخة من القديمة
  insert into public.women_members
  select (jsonb_populate_record(
            null::public.women_members,
            to_jsonb(w) || jsonb_build_object('id', p_new)
         )).*
    from public.women_members w
   where w.id = p_old
  on conflict (id) do nothing;

  for c in
    select con.conrelid::regclass as tbl, att.attname as col
      from pg_constraint con
      join pg_attribute att
        on att.attrelid = con.conrelid and att.attnum = con.conkey[1]
     where con.contype = 'f'
       and con.confrelid = 'public.women_members'::regclass
       and array_length(con.conkey, 1) = 1
  loop
    -- بلا تخطٍّ صامت: فشل أي نقل يُلغي العملية كلها بدل فصل أحد
    execute format('update %s set %I = $1 where %I = $2', c.tbl, c.col, c.col)
      using p_new, p_old;
  end loop;
end;
$function$;

revoke all on function public.repoint_women_node(uuid, uuid) from public, anon, authenticated;

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

  -- جديد (٢٠٢٦-١٠-٠١): عقدة شجرة النساء ومن يشير لها (الزوجة، البنات) تنتقل للمعرّف
  -- الجديد قبل حذف القديم — كان الحذف يفرّغ روابطهن بصمت. قبل حلقة profiles لأن نقل
  -- father_id للأبناء يحدّث عقدهم بأب جديد يجب أن تكون عقدته موجودة.
  perform public.repoint_women_node(p_tree_id, p_auth_uid);

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

  -- إن بقي أحد من العائلة مربوطاً بالقديم يرفض الحارس الحذف فيُلغى النقل كله (لا فصل)
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

-- ─── ٥) دمج الزوجة المكررة: لا يحذف سجلاً ما زال له تابعون ────────────────────────
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

  -- احذف السجلات المنفصلة المكررة — فقط ما لم يبقَ له تابعون (لا فصل لأحد).
  delete from public.women_members d
   where d.id = any(dup_ids)
     and not exists (
       select 1 from public.women_members x
        where x.id <> d.id
          and (x.parent_id = d.id or x.mother_id = d.id or x.husband_id = d.id));

  return new;
end;
$function$;
