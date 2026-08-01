-- ═══════════════════════════════════════════════════════════════════════════
-- إصلاح تسجيل الدخول لأعضاء الشجرة عند أول دخول (أندرويد/ويب/iOS) — 2026-07-07
--
-- المشكلة (سبب "تسجيل الدخول مو شغال" على أندرويد):
--   Supabase Auth يخزّن رقم المستخدم بصيغة E.164 بدون + (مثال: 96597660155)،
--   بينما جدول profiles يخزّن الأرقام الكويتية محلية 8 أرقام (97660155) بفعل
--   trg_profiles_normalize_phone. دالة handle_new_user_by_phone كانت تطابق
--   حرفياً `phone_number = new.phone` → المطابقة تفشل دائماً للأرقام الكويتية:
--     1) لا يُربط الحساب الجديد بعضو الشجرة، ويُنشأ سجل جديد بلا اسم بدله.
--     2) تطبيق iOS يتجاوز المشكلة بمنطق بحث/ربط داخل التطبيق، أما أندرويد
--        فيقرأ profiles بـ id = auth.uid() فقط → يظهر للعضو شاشة "تسجيل جديد"
--        بدل حسابه (يفهمها المستخدم أن الدخول لا يعمل).
--   إضافةً لذلك، مسار الربط القديم `update profiles set id = new.id` يفشل
--   بقيد FK لأي عضو له أبناء (father_id يشير إليه) — فلا يصلح كأسلوب ربط.
--
-- الإصلاح:
--   1) دالة find_profile_id_by_auth_phone: مطابقة بعد التطبيع + آخر 8 أرقام.
--   2) دالة adopt_tree_profile: تبنّي سجل الشجرة على auth.uid ذرّياً —
--      نسخ البيانات، إعادة توجيه كل المراجع (FK ديناميكياً + sons_ids)،
--      ثم حذف السجل القديم. نفس فكرة merge_member_into_tree لكن تلقائياً
--      عند الدخول وبتغطية أوسع للجداول.
--   3) إعادة كتابة handle_new_user_by_phone لاستخدامهما، مع إدراج الرقم
--      مطبَّعاً عند إنشاء سجل جديد (يمنع تعارض unique index الذي كان يُفشل
--      إنشاء حساب الدخول نفسه: "Database error saving new user").
--   4) إعادة ترتيب triggers جدول profiles بحيث يعمل التطبيع قبل فحص تحرير
--      الرقم المتعارض (كان الفحص يقارن قيمة غير مطبَّعة فلا يجد التعارض).
--   5) إصلاح بيانات: ربط حسابات الدخول القائمة العالقة (سجل ناقص/بلا اسم)
--      بعضو الشجرة المطابق لرقمها — يشمل الحالة المبلَّغ عنها 97660155.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── 1) أفضل عضو شجرة مطابق لرقم auth ───────────────────────────────────────
create or replace function public.find_profile_id_by_auth_phone(
  p_auth_phone text,
  p_exclude    uuid default null
)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_norm text;
  v_id   uuid;
begin
  if p_auth_phone is null or btrim(p_auth_phone) = '' then
    return null;
  end if;

  -- رقم auth يأتي بدون + (96597660155) → نطبّعه لصيغة التخزين (97660155)
  v_norm := public.normalize_kuwait_phone(
    case when p_auth_phone like '+%' then p_auth_phone else '+' || p_auth_phone end
  );
  if v_norm is null then
    return null;
  end if;

  select p.id into v_id
  from public.profiles p
  where (p_exclude is null or p.id <> p_exclude)
    and coalesce(btrim(p.full_name), '') <> ''          -- عضو حقيقي وليس سجلاً فارغاً
    and p.phone_number is not null
    and (p.phone_number = v_norm
         or public.phones_match_suffix(p.phone_number, v_norm))
  order by
    (p.phone_number = v_norm) desc,                     -- المطابقة الحرفية أولاً
    (p.status = 'active') desc,
    (p.role <> 'pending') desc,
    p.created_at asc,
    p.id asc
  limit 1;

  return v_id;
end;
$$;

-- ─── 2) تبنّي سجل الشجرة على معرف حساب الدخول ───────────────────────────────
-- ينقل هوية عضو الشجرة (p_tree_id) إلى الصف ذي المعرف p_auth_uid ثم يعيد
-- توجيه كل الجداول المُشيرة ويحذف الصف القديم. أي فشل يُرجِع الحالة كما كانت.
create or replace function public.adopt_tree_profile(
  p_auth_uid uuid,
  p_tree_id  uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
$$;

-- ─── 3) ربط الحساب الجديد بعضو الشجرة عند إنشائه ────────────────────────────
create or replace function public.handle_new_user_by_phone()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_norm    text;
  v_tree_id uuid;
begin
  if new.phone is not null and btrim(new.phone) <> '' then
    v_norm := public.normalize_kuwait_phone(
      case when new.phone like '+%' then new.phone else '+' || new.phone end
    );

    -- عضو موجود بالشجرة بنفس الرقم → ربط الحساب الجديد بسجله (ذرّياً)
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

    -- رقم غير معروف → سجل جديد بانتظار الربط/الموافقة (بالرقم المطبَّع حتى
    -- لا يصطدم بـ unique index بصيغة مختلفة)
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
$$;

-- ─── 4) التطبيع قبل فحص تحرير الرقم المتعارض ────────────────────────────────
-- triggers الـ BEFORE تُنفَّذ أبجدياً: كان profiles_free_conflicting_phone يعمل
-- قبل profiles_normalize_phone فيقارن رقماً غير مطبَّع ولا يجد التعارض، ثم
-- يفشل الإدراج بالقيد الفريد. نعيد إنشاء trigger التطبيع باسم يسبق الجميع.
drop trigger if exists profiles_normalize_phone on public.profiles;
drop trigger if exists profiles_0_normalize_phone on public.profiles;
create trigger profiles_0_normalize_phone
  before insert or update of phone_number on public.profiles
  for each row
  execute function public.trg_profiles_normalize_phone();

-- ─── 5) شفاء ذاتي: ربط حساب الدخول عند إضافة رقم لعضو مسمّى ─────────────────
-- الحالة: حساب دخول قائم وسجله بلا اسم (أنشأه الـ trigger القديم)، والإدارة
-- تعيد إضافة الرقم لعضو الشجرة من شاشة "تعديل / إضافة رقم العضو" → نربط فوراً
-- حساب الدخول بسجل العضو، فيعمل تطبيقه عند التشغيل التالي بدون أي خطوة إضافية.
create or replace function public.trg_profiles_link_auth_on_phone_set()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_auth_uid uuid;
begin
  -- يهمنا فقط عضو مسمّى حصل على رقم
  if new.phone_number is null or btrim(new.phone_number) = ''
     or coalesce(btrim(new.full_name), '') = '' then
    return new;
  end if;

  -- حساب دخول بنفس الرقم، سجله في profiles مفقود أو بلا اسم
  select au.id into v_auth_uid
  from auth.users au
  where au.id <> new.id
    and au.phone is not null
    and public.phones_match_suffix(au.phone, new.phone_number)
    and not exists (
      select 1 from public.profiles p
      where p.id = au.id
        and coalesce(btrim(p.full_name), '') <> ''
    )
  limit 1;

  if v_auth_uid is not null then
    begin
      perform public.adopt_tree_profile(v_auth_uid, new.id);
    exception when others then
      raise warning '[AUTH-LINK] فشل الربط الذاتي لحساب %: %', v_auth_uid, sqlerrm;
    end;
  end if;

  return new;
end;
$$;

drop trigger if exists profiles_link_auth_on_phone_set on public.profiles;
create trigger profiles_link_auth_on_phone_set
  after insert or update of phone_number on public.profiles
  for each row
  execute function public.trg_profiles_link_auth_on_phone_set();

-- ─── 6) إصلاح بيانات: ربط الحسابات العالقة القائمة ──────────────────────────
-- كل حساب دخول برقم هاتف، سجله في profiles مفقود أو بلا اسم (سجل أنشأه
-- الـ trigger القديم)، وله عضو شجرة مطابق بالرقم → يُربط الآن.
do $$
declare
  u         record;
  v_tree_id uuid;
  v_fixed   int := 0;
begin
  for u in
    select au.id, au.phone
    from auth.users au
    where au.phone is not null
      and not exists (
        select 1 from public.profiles p
        where p.id = au.id
          and coalesce(btrim(p.full_name), '') <> ''
      )
  loop
    v_tree_id := public.find_profile_id_by_auth_phone(u.phone, u.id);
    if v_tree_id is not null then
      begin
        perform public.adopt_tree_profile(u.id, v_tree_id);
        v_fixed := v_fixed + 1;
        raise notice '[REPAIR] رُبط حساب % (هاتف %) بالعضو %', u.id, u.phone, v_tree_id;
      exception when others then
        raise warning '[REPAIR] تعذر ربط حساب % بالعضو %: %', u.id, v_tree_id, sqlerrm;
      end;
    end if;
  end loop;
  raise notice '[REPAIR] تم ربط % حساب/حسابات عالقة', v_fixed;
end $$;
