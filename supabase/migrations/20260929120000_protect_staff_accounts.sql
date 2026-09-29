-- حماية حسابات الإدارة من النقل والسرقة (طلب المالك ٢٠٢٦-٠٩-٢٩)
--
-- ما حدث: يوم ٢٠٢٦-٠٩-٢٤ انخلق حساب دخول جديد برقم المالك، فنقل
-- handle_new_user_by_phone ← adopt_tree_profile ملفه إلى المعرّف الجديد وحذف
-- الصف القديم (9849ab4f… ← 88d7b2f2…) — فانفصلت أجهزته وضاع ما لم يُنقل.
-- حماية المالك في adopt أُضيفت ٢٠٢٦-٠٩-٢٨؛ هنا نكملها:
--   ١) adopt_tree_profile: لا نقل تلقائي لملفات الإدارة كلها (مالك/مدير/مراقب/مشرف).
--   ٢) تحرير الرقم المتعارض عند إدراج عضو: لا يُسحب رقم الإدارة ولا رقم عضو مربوط
--      بحساب دخول متحقَّق من رقمه — يُرفض الإدراج بـ phone_in_use بدل إفراغ رقمه.
--   ٣) handle_new_user_by_phone: فشل إنشاء السجل المبدئي لا يمنع إنشاء حساب الدخول.
--   ٤) سجل المالك لا يُحذف إلا يدوياً من لوحة التحكم (لا من التطبيق ولا من أي آلية).
--
-- التراجع: أعِد تطبيق تعريفات الدوال الأربع كما كانت قبل هذا الملف
-- (محفوظة في supabase/rollback/20260929120000_protect_staff_accounts_rollback.sql).

-- ─── ١) النقل التلقائي: لا لملفات الإدارة ──────────────────────────────────
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

  -- حماية: ملفات الإدارة (المالك/المدير/المراقب/المشرف) لا تُنقل تلقائياً أبداً —
  -- نقلها يدوي ومقصود فقط
  if v_tree.role in ('owner', 'admin', 'monitor', 'supervisor') then
    raise warning '[ADOPT] رُفض نقل ملف الإدارة % (%) إلى %', p_tree_id, v_tree.role, p_auth_uid;
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
    -- 2.2ب) يوجد صف ناقص → ننقل إليه هوية الشجرة
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

  -- 2.3) إعادة توجيه كل الأعمدة المُشيرة إلى profiles(id)
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

-- ─── ٢) الرقم المتعارض عند إدراج عضو: لا يُسحب رقم الإدارة ولا المرتبط المتحقَّق ──
create or replace function public.trg_profiles_free_conflicting_phone()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
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

  -- صاحب الرقم من الإدارة، أو مربوط بحساب دخول متحقَّق من هذا الرقم → رقمه لا يُفرَّغ
  if exists (
       select 1 from public.profiles h
       where h.id = v_conflicting_id
         and h.role in ('owner', 'admin', 'monitor', 'supervisor')
     )
     or exists (
       select 1 from auth.users u
       where u.id = v_conflicting_id
         and u.phone_confirmed_at is not null
         and public.phones_match_suffix(u.phone, new.phone_number)
     ) then
    raise exception 'phone_in_use' using errcode = '23505',
      hint = 'هذا الرقم مسجّل لعضو آخر';
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
$function$;

-- ─── ٣) حساب الدخول الجديد يُنشأ دائماً حتى لو تعذّر سجله المبدئي ──────────────
create or replace function public.handle_new_user_by_phone()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_norm    text;
  v_tree_id uuid;
begin
  if new.phone is not null and btrim(new.phone) <> '' then
    v_norm := public.normalize_kuwait_phone(
      case when new.phone like '+%' then new.phone else '+' || new.phone end
    );

    -- عضو موجود بالشجرة بنفس الرقم → ربط الحساب الجديد بسجله (ذرّياً)
    -- (ملفات الإدارة والمربوطة بحساب متحقَّق لا تُنقل — تُرفض داخل adopt)
    v_tree_id := public.find_profile_id_by_auth_phone(new.phone, new.id);
    if v_tree_id is not null then
      begin
        perform public.adopt_tree_profile(new.id, v_tree_id);
        return new;
      exception when others then
        -- الربط التلقائي يجب ألا يمنع إنشاء حساب الدخول إطلاقاً
        raise warning '[AUTH-LINK] فشل ربط % بالعضو %: %', new.id, v_tree_id, sqlerrm;
      end;
    end if;

    -- رقم غير معروف → سجل جديد بانتظار الربط/الموافقة — وفشله (رقم محمي مثلاً)
    -- لا يُفشل إنشاء حساب الدخول
    begin
      insert into public.profiles (id, phone_number, full_name, first_name, role, status)
      values (
        new.id,
        coalesce(v_norm, new.phone),
        coalesce(new.raw_user_meta_data->>'full_name', ''),
        coalesce(split_part(new.raw_user_meta_data->>'full_name', ' ', 1), ''),
        'member',
        'pending'
      )
      on conflict (id) do nothing;
    exception when others then
      raise warning '[AUTH-LINK] تعذّر إنشاء السجل المبدئي لـ %: %', new.id, sqlerrm;
    end;

  else
    -- تسجيل عبر الموقع (email/password) — ينتظر موافقة الإدارة
    insert into public.profiles (id, full_name, first_name, role, status)
    values (
      new.id,
      coalesce(new.raw_user_meta_data->>'full_name', ''),
      coalesce(split_part(new.raw_user_meta_data->>'full_name', ' ', 1), ''),
      'pending',
      'pending'
    )
    on conflict (id) do nothing;
  end if;

  return new;
end;
$function$;

-- ─── ٤) سجل المالك لا يُحذف إلا يدوياً من لوحة التحكم ─────────────────────────
create or replace function public.trg_profiles_protect_delete()
 returns trigger
 language plpgsql
as $function$
begin
  -- المالك: لا حذف من التطبيق ولا من أي آلية (دوال/ربط/مهام) — يدوياً من لوحة التحكم فقط
  if old.role = 'owner' and session_user not in ('postgres', 'supabase_admin') then
    raise exception 'owner_protected'
      using hint = 'لا يمكن حذف المالك';
  end if;
  if auth.uid() is not null then
    if old.id = auth.uid() then
      raise exception 'cannot_delete_self'
        using hint = 'لا يمكن حذف سجلك من لوحة الإدارة';
    end if;
  end if;
  return old;
end;
$function$;
