-- مطابقة التطبيق للخصوصية والشروط (طلب المالك ٢٠٢٦-١٠-٢٨، «٢»):
--  أ) حذف الحساب طلب تنفّذه الإدارة خلال ٧ أيام (المادة ٩ من الخصوصية) — account_delete.
--  ب) لا حساب دون ١٣، ومن ١٣ إلى ١٧ بموافقة ولي الأمر من حسابه موثّقة (المادة ١ من الشروط) — guardian_consents.
--  ج) إخفاء الصورة وتاريخ الميلاد عن الأعضاء (المادة ٥) — members_masked يخفيهما لغير صاحبهما والإدارة.
--  د) طلب إخفاء/حذف/تصحيح بياناته، والبيانات تُخفى مؤقتاً أثناء المراجعة (المادة ٩) — privacy_request.
--  هـ) سبب تعليق العضوية يُبلَّغ للعضو (المادة ٦ من الشروط) — profiles.frozen_reason.
-- التراجع: supabase/rollback/20261028180000_terms_compliance_rollback.sql

create or replace function public.age_years(p_birth date)
returns integer language sql stable set search_path = public as $$
  select case when p_birth is null then null
              else extract(year from age((now() at time zone 'Asia/Kuwait')::date, p_birth))::int end
$$;

alter table public.profiles add column if not exists is_photo_hidden boolean not null default false;
alter table public.profiles add column if not exists frozen_reason text;

-- ═══ أ) طلب حذف الحساب ═══
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
       'phone_change','child_add','news_report','content_report','account_delete','privacy_request') then
    raise exception 'admin_request_type_not_allowed' using errcode = '42501';
  end if;
  if new.requester_id is null
     or (new.requester_id is distinct from me and new.requester_id is distinct from my_profile) then
    raise exception 'admin_request_requester_not_self' using errcode = '42501';
  end if;
  if new.member_id is null then
    raise exception 'admin_request_member_required' using errcode = '42501';
  end if;
  if new.request_type not in ('link_request','contact_message','account_delete') and not public.is_approved_member() then
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

create or replace function public.account_auth_id(p_profile_id uuid)
returns uuid language sql stable security definer set search_path = '' as $$
  select u.id from auth.users u
   where u.id = p_profile_id or u.raw_app_meta_data ->> 'profile_id' = p_profile_id::text
   order by (u.id = p_profile_id) desc limit 1
$$;
revoke execute on function public.account_auth_id(uuid) from public, anon, authenticated;

create or replace function public.my_account_deletion_request()
returns jsonb language sql stable security definer set search_path = public as $$
  select to_jsonb(x) from (
    select r.id, r.created_at, r.status from public.admin_requests r
     where r.request_type = 'account_delete' and r.status = 'pending'
       and r.member_id = coalesce(public.current_profile_id(), auth.uid())
     order by r.created_at desc limit 1) x
$$;

create or replace function public.request_account_deletion()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me uuid := coalesce(public.current_profile_id(), auth.uid());
  existing jsonb;
  rid uuid;
  m_name text;
begin
  if me is null then raise exception 'not_authenticated' using hint = 'not_authenticated'; end if;
  if exists (select 1 from public.profiles p where p.id = me and p.role = 'owner') then
    raise exception 'حساب مالك التطبيق محمي. يلزم نقل الملكية قبل حذفه.' using hint = 'owner_protected';
  end if;
  existing := public.my_account_deletion_request();
  if existing is not null then return existing; end if;
  insert into public.admin_requests (member_id, requester_id, request_type, status, details)
  values (me, me, 'account_delete', 'pending', 'طلب حذف الحساب') returning id into rid;
  m_name := coalesce((select full_name from public.profiles where id = me), '');
  insert into public.notifications (target_member_id, title, body, kind, created_by, request_id, request_type)
  values (null, 'طلب حذف حساب', m_name || ' طلب حذف حسابه — يُنفَّذ خلال ٧ أيام', 'account_delete', me, rid, 'account_delete');
  return public.my_account_deletion_request();
end $$;

create or replace function public.cancel_account_deletion_request()
returns boolean language plpgsql security definer set search_path = public as $$
declare me uuid := coalesce(public.current_profile_id(), auth.uid());
begin
  delete from public.admin_requests
   where request_type = 'account_delete' and status = 'pending' and member_id = me;
  return found;
end $$;

create or replace function public.reject_account_deletion(p_request_id uuid, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.admin_requests%rowtype;
begin
  if coalesce(public.current_user_role(), '') not in ('owner', 'admin') then
    raise exception 'not_allowed' using errcode = '42501', hint = 'not_allowed';
  end if;
  select * into r from public.admin_requests where id = p_request_id and request_type = 'account_delete' for update;
  if not found then raise exception 'request_not_found' using hint = 'request_not_found'; end if;
  if r.status <> 'pending' then raise exception 'already_handled' using hint = 'already_handled'; end if;
  update public.admin_requests set status = 'rejected', admin_reply = p_reason, replied_at = now(),
         replied_by = public.current_profile_id() where id = r.id;
  insert into public.notifications (target_member_id, title, body, kind, created_by)
  values (r.member_id, 'طلب حذف الحساب', 'لم يُنفَّذ طلب حذف حسابك' || coalesce(E'\nالسبب: ' || p_reason, ''),
          'request_rejected', public.current_profile_id());
  return jsonb_build_object('ok', true);
end $$;

-- ═══ ب) العمر وموافقة ولي الأمر ═══
create table if not exists public.guardian_consents (
  id uuid primary key default gen_random_uuid(),
  minor_id uuid not null,
  tree_member_id uuid,
  guardian_id uuid not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  scope text not null default 'إنشاء حساب في تطبيق «عائلة المحمدعلي» واستخدامه وفق سياسة الخصوصية وقواعد الاستخدام',
  requested_by uuid,
  created_at timestamptz not null default now(),
  decided_at timestamptz
);
create index if not exists guardian_consents_minor_idx on public.guardian_consents (minor_id);
create index if not exists guardian_consents_guardian_idx on public.guardian_consents (guardian_id, status);
alter table public.guardian_consents enable row level security;
drop policy if exists guardian_consents_select on public.guardian_consents;
create policy guardian_consents_select on public.guardian_consents for select to authenticated
  using (guardian_id = public.current_profile_id() or minor_id = public.current_profile_id()
         or coalesce(public.current_user_role(), '') in ('owner', 'admin', 'monitor'));
revoke all on public.guardian_consents from anon;

create or replace function public.has_guardian_consent(p_minor uuid, p_tree uuid default null)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.guardian_consents g where g.status = 'approved'
                 and (g.minor_id = p_minor or g.tree_member_id = p_minor
                      or (p_tree is not null and (g.tree_member_id = p_tree or g.minor_id = p_tree))))
$$;

create or replace function public.request_guardian_consent(p_minor uuid, p_tree_member uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  g uuid;
  cid uuid;
  minor_name text;
begin
  if coalesce(public.current_user_role(), '') not in ('owner', 'admin', 'monitor') then
    raise exception 'not_allowed' using errcode = '42501', hint = 'not_allowed';
  end if;
  select father_id, full_name into g, minor_name from public.profiles where id = p_tree_member;
  if g is null then
    raise exception 'لا يوجد أب مسجّل لهذا العضو في الشجرة.' using hint = 'no_guardian';
  end if;
  if not public.profile_has_login(g) then
    raise exception 'ولي الأمر ليس لديه حساب في التطبيق، فلا يمكن طلب موافقته.' using hint = 'guardian_no_account';
  end if;
  select id into cid from public.guardian_consents
   where minor_id = p_minor and guardian_id = g and status = 'pending' limit 1;
  if cid is null then
    insert into public.guardian_consents (minor_id, tree_member_id, guardian_id, requested_by)
    values (p_minor, p_tree_member, g, public.current_profile_id()) returning id into cid;
    insert into public.notifications (target_member_id, title, body, kind, created_by, subject_member_id)
    values (g, 'موافقة ولي الأمر',
            '«' || coalesce(minor_name, '') || '» طلب إنشاء حساب في التطبيق، ويلزم موافقتك بصفتك ولي أمره. افتح «حسابي» للموافقة أو الرفض.',
            'guardian_consent', public.current_profile_id(), p_tree_member);
  end if;
  return jsonb_build_object('ok', true, 'consent_id', cid, 'guardian_id', g);
end $$;

create or replace function public.my_guardian_requests()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', g.id, 'minor_name', coalesce(t.full_name, m.full_name), 'created_at', g.created_at, 'scope', g.scope)
           order by g.created_at), '[]'::jsonb)
    from public.guardian_consents g
    left join public.profiles t on t.id = g.tree_member_id
    left join public.profiles m on m.id = g.minor_id
   where g.guardian_id = public.current_profile_id() and g.status = 'pending'
$$;

create or replace function public.decide_guardian_consent(p_consent_id uuid, p_approve boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  c public.guardian_consents%rowtype;
  minor_name text;
begin
  select * into c from public.guardian_consents where id = p_consent_id for update;
  if not found or c.guardian_id is distinct from public.current_profile_id() then
    raise exception 'not_allowed' using errcode = '42501', hint = 'not_allowed';
  end if;
  if c.status <> 'pending' then raise exception 'already_handled' using hint = 'already_handled'; end if;
  update public.guardian_consents set status = case when p_approve then 'approved' else 'rejected' end,
         decided_at = now() where id = c.id;
  minor_name := coalesce((select full_name from public.profiles where id = coalesce(c.tree_member_id, c.minor_id)), '');
  insert into public.notifications (target_member_id, title, body, kind, created_by, subject_member_id)
  values (null, 'موافقة ولي الأمر',
          case when p_approve then 'وافق ولي الأمر على حساب «' || minor_name || '» — يمكن تفعيله الآن'
               else 'رفض ولي الأمر حساب «' || minor_name || '»' end,
          'guardian_consent', public.current_profile_id(), coalesce(c.tree_member_id, c.minor_id));
  return jsonb_build_object('ok', true, 'status', case when p_approve then 'approved' else 'rejected' end);
end $$;

-- التسجيل: من دون ١٣ لا يُنشئ حساباً لنفسه، والإدارة لا تفعّل قاصراً بلا موافقة ولي أمره
create or replace function public.trg_profiles_age_rules()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  me uuid := coalesce(public.current_profile_id(), auth.uid());
  a int := public.age_years(new.birth_date);
begin
  if auth.role() is distinct from 'authenticated' then return new; end if;
  if coalesce(public.current_user_role(), '') in ('owner', 'admin', 'monitor') then
    if tg_op = 'UPDATE' and new.status = 'active' and old.status is distinct from 'active'
       and a is not null and a < 18 and public.profile_has_login(new.id) then
      if a < 13 then
        raise exception 'لا يُنشأ حساب لمن هم دون الثالثة عشرة؛ يُدرَج في الشجرة من خلال ولي أمره.' using hint = 'under_13';
      elsif not public.has_guardian_consent(new.id) then
        raise exception 'العضو قاصر: يلزم موافقة ولي أمره من حسابه في التطبيق قبل تفعيل حسابه.' using hint = 'guardian_consent_required';
      end if;
    end if;
    return new;
  end if;
  if new.id = me and a is not null and a < 13 then
    raise exception 'لا يمكن إنشاء حساب لمن هم دون الثالثة عشرة. يمكن لولي أمرك إضافتك إلى شجرة العائلة.' using hint = 'under_13';
  end if;
  return new;
end $$;
drop trigger if exists trg_profiles_age_rules on public.profiles;
create trigger trg_profiles_age_rules before insert or update of birth_date, status on public.profiles
  for each row execute function public.trg_profiles_age_rules();

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

  -- ─── المادة (١) من الشروط (٢٠٢٦-١٠-٢٨): لا حساب دون ١٣، ومن ١٣ إلى ١٧ بعد موافقة ولي الأمر ───
  if public.age_years(coalesce(v_new.birth_date, v_tree.birth_date)) < 13 then
    return jsonb_build_object('success', false, 'hint', 'under_13',
      'message', 'لا يُنشأ حساب لمن هم دون الثالثة عشرة؛ يُدرَج في الشجرة من خلال ولي أمره.');
  end if;
  if public.age_years(coalesce(v_new.birth_date, v_tree.birth_date)) between 13 and 17
     and not public.has_guardian_consent(p_new_member_id, p_tree_member_id) then
    return jsonb_build_object('success', false, 'hint', 'guardian_consent_required',
      'message', 'العضو قاصر: يلزم موافقة ولي أمره من حسابه في التطبيق قبل تفعيل حسابه.');
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
    -- الإخفاء المؤقت أثناء «طلب الخصوصية» (request_privacy_change وحده يضبط العلم داخل معاملته)
    or (new.is_hidden_from_tree is distinct from old.is_hidden_from_tree
        and not (coalesce(current_setting('family.privacy_hold', true), '') = 'on' and new.is_hidden_from_tree))
    or new.family_name is distinct from old.family_name) then
    raise exception 'self_edit_forbidden' using errcode = '42501',
      hint = 'هذه البيانات تتعدل عبر طلب للإدارة';
  end if;

  return new;
end;
$function$;

-- ═══ ج) إخفاء الصورة وتاريخ الميلاد ═══
create or replace view public.members_masked as
SELECT id,
    first_name,
    full_name,
        CASE
            WHEN COALESCE(is_phone_hidden, false) = false OR id = auth.uid() OR is_team(auth.uid()) THEN phone_number
            ELSE NULL::text
        END AS phone_number,
        CASE
            WHEN COALESCE(is_birth_date_hidden, false) = false OR id = auth.uid() OR id = current_profile_id() OR is_team(auth.uid()) THEN birth_date
            ELSE NULL::date
        END AS birth_date,
    death_date,
    is_deceased,
    role,
    father_id,
        CASE
            WHEN COALESCE(is_photo_hidden, false) = false OR id = auth.uid() OR id = current_profile_id() OR is_team(auth.uid()) THEN photo_url
            ELSE NULL::text
        END AS photo_url,
    is_phone_hidden,
    is_hidden_from_tree,
    sort_order,
    bio_json,
    sons_ids,
    status,
    created_at,
    is_married,
        CASE
            WHEN COALESCE(is_photo_hidden, false) = false OR id = auth.uid() OR id = current_profile_id() OR is_team(auth.uid()) THEN avatar_url
            ELSE NULL::text
        END AS avatar_url,
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
    avatar_unavailable,
    is_photo_hidden
   FROM profiles p
  WHERE auth.uid() IS NOT NULL AND (id = auth.uid() OR is_approved_member());

-- ═══ د) طلب الخصوصية: إخفاء/حذف/تصحيح، والإخفاء المؤقت أثناء المراجعة ═══
create or replace function public.request_privacy_change(p_kind text, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me uuid := coalesce(public.current_profile_id(), auth.uid());
  prev boolean;
  rid uuid;
  m_name text;
begin
  if me is null then raise exception 'not_authenticated' using hint = 'not_authenticated'; end if;
  if p_kind not in ('hide', 'delete', 'correct') then raise exception 'bad_kind' using hint = 'bad_payload'; end if;
  select coalesce(is_hidden_from_tree, false), full_name into prev, m_name from public.profiles where id = me;
  insert into public.admin_requests (member_id, requester_id, request_type, status, details, new_value)
  values (me, me, 'privacy_request', 'pending',
          jsonb_build_object('kind', p_kind, 'note', coalesce(p_note, ''), 'prev_hidden', prev)::text, p_kind)
  returning id into rid;
  if p_kind in ('hide', 'delete') then
    perform set_config('family.privacy_hold', 'on', true);
    update public.profiles set is_hidden_from_tree = true where id = me;
    perform set_config('family.privacy_hold', '', true);
  end if;
  insert into public.notifications (target_member_id, title, body, kind, created_by, request_id, request_type)
  values (null, 'طلب خصوصية',
          coalesce(m_name, '') || case p_kind when 'hide' then ' طلب إخفاء بياناته' when 'delete' then ' طلب حذف بياناته من الشجرة'
                                      else ' طلب تصحيح بياناته' end,
          'privacy_request', me, rid, 'privacy_request');
  return jsonb_build_object('ok', true, 'request_id', rid, 'hidden_now', p_kind in ('hide', 'delete'));
end $$;

create or replace function public.decide_privacy_request(p_request_id uuid, p_approve boolean, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  r public.admin_requests%rowtype;
  d jsonb;
begin
  if coalesce(public.current_user_role(), '') not in ('owner', 'admin', 'monitor') then
    raise exception 'not_allowed' using errcode = '42501', hint = 'not_allowed';
  end if;
  select * into r from public.admin_requests where id = p_request_id and request_type = 'privacy_request' for update;
  if not found then raise exception 'request_not_found' using hint = 'request_not_found'; end if;
  if r.status <> 'pending' then raise exception 'already_handled' using hint = 'already_handled'; end if;
  d := r.details::jsonb;
  if not p_approve and d->>'kind' in ('hide', 'delete') then
    update public.profiles set is_hidden_from_tree = coalesce((d->>'prev_hidden')::boolean, false) where id = r.member_id;
  end if;
  update public.admin_requests set status = case when p_approve then 'approved' else 'rejected' end,
         admin_reply = p_reason, replied_at = now(), replied_by = public.current_profile_id() where id = r.id;
  insert into public.notifications (target_member_id, title, body, kind, created_by)
  values (r.member_id, 'طلب الخصوصية',
          case when p_approve then 'تمت الموافقة على طلبك' else 'لم تتم الموافقة على طلبك' end || coalesce(E'\nالسبب: ' || p_reason, ''),
          case when p_approve then 'request_approved' else 'request_rejected' end, public.current_profile_id());
  return jsonb_build_object('ok', true);
end $$;

-- ═══ هـ) تعليق العضوية بسبب يُبلَّغ ═══
create or replace function public.set_member_suspension(p_member uuid, p_suspend boolean, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if coalesce(public.current_user_role(), '') not in ('owner', 'admin') then
    raise exception 'not_allowed' using errcode = '42501', hint = 'not_allowed';
  end if;
  if exists (select 1 from public.profiles where id = p_member and role = 'owner') then
    raise exception 'not_allowed' using errcode = '42501', hint = 'owner_protected';
  end if;
  update public.profiles set status = case when p_suspend then 'frozen' else 'active' end,
         frozen_reason = case when p_suspend then v_reason end
   where id = p_member;
  insert into public.notifications (target_member_id, title, body, kind, created_by)
  values (p_member, case when p_suspend then 'تعليق العضوية' else 'إعادة تفعيل العضوية' end,
          case when p_suspend then 'عُلّقت عضويتك' || coalesce(E'\nالسبب: ' || v_reason, '')
                                   || E'\nيمكنك الاعتراض من «التواصل» خلال ٧ أيام.'
               else 'أُعيد تفعيل عضويتك' end,
          'account_status', public.current_profile_id());
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.my_suspension()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('frozen', p.status = 'frozen', 'reason', p.frozen_reason)
    from public.profiles p where p.id = coalesce(public.current_profile_id(), auth.uid())
$$;

do $$
declare f text;
begin
  foreach f in array array['my_account_deletion_request()','request_account_deletion()','cancel_account_deletion_request()',
    'reject_account_deletion(uuid,text)','request_guardian_consent(uuid,uuid)','my_guardian_requests()',
    'decide_guardian_consent(uuid,boolean)','request_privacy_change(text,text)','decide_privacy_request(uuid,boolean,text)',
    'set_member_suspension(uuid,boolean,text)','my_suspension()','has_guardian_consent(uuid,uuid)'] loop
    execute format('revoke execute on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
