-- «أسرة البنت» على السيرفر — مواءمة 20261109200000_daughter_family_visibility (طلب المالك ٢٠٢٦-١١-١٨ «جهزها»)
--
-- ذلك الترحيل لم يُطبَّق على السيرفر قط، فأزرار البنت من حسابها (إضافة الزوج، إضافة الأبناء، الظهور، الترتيب)
-- تستدعي دوالّ غير موجودة. وتطبيقه كما هو يعيد نسخة قديمة من `decide_admin_request` تمسح ما أضافه
-- 20261113130000 (طلبات الحذف relative_remove وسجلّها). هذا الترحيل = كل ما فيه حرفياً عدا تعريف
-- `decide_admin_request`؛ والقبول يُرقَّع في الدالة الحيّة بالنصّ (فرعا women_family_set_husband /
-- women_family_add_child) — يرفض التطبيق إن تغيّرت الدالة.
--
-- القواعد المعتمدة:
--   • الزوج: البنت وحدها تتحكم في ظهوره جنبها (لا الزوج نفسه). الافتراضي مخفي — إلا وفيقة (زوجها مسعود ظاهر).
--   • الأم: تظهر دائماً — بلا مفتاح.
--   • البنت تتحكم في ظهورها هي (is_hidden_from_tree على عقدتها).
--   • عيالها من زوج من خارج العائلة: مخفيون تحتها افتراضياً إلا بطلبها، ولها إخفاء واحد بعينه.
--   • إضافة الزوج وإضافة الأبناء تمرّ بمسار «إضافة قريبة» نفسه (relative_add) — موافقة الإدارة متى ما
--     كان self_relative_requires_approval شغالاً، والإدارة تنفّذ مباشرة.
--   • البنت المتوفاة (طلبات الأقرباء، والإخفاء يغلب): المرحلة الثانية — ليست هنا.
--
-- الأعمدة كلها nullable: null = الافتراضي (فلا تحديث جماعي ولا إشعارات ولا سجل نشاط لآلاف الصفوف).
--   spouse_shown   : للبنت = زوجها جنبها (null → مخفي). للرجل محجوز (null → زوجاته كما هن).
--   children_shown : للبنت = عيالها من زوج من خارج العائلة تحتها (null → مخفيون).
--   hidden_children: عيال بعينهم أخفتهم (يُطبّق متى ما children_shown = true).

alter table public.women_members
  add column if not exists spouse_shown    boolean,
  add column if not exists children_shown  boolean,
  add column if not exists hidden_children uuid[];

comment on column public.women_members.spouse_shown    is 'للبنت: زوجها يظهر جنبها في شجرة النساء (null = مخفي). تتحكم فيه هي — women_family_set_visibility';
comment on column public.women_members.children_shown  is 'للبنت: عيالها من زوج من خارج العائلة يظهرون تحتها (null = مخفيون)';
comment on column public.women_members.hidden_children is 'للبنت: عيال بعينهم أخفتهم من تحتها';

-- الوضع الحالي كما هو: مسعود جنب وفيقة وابنها تحتها
update public.women_members
   set spouse_shown = true, children_shown = true
 where id = '8882a26e-0e7e-47f6-bef9-e1b198f17c5f'
   and husband_id = 'f7734bb8-76f5-4666-87c8-d6c678525a02';

-- ─────────────────────────────────────────────────────────────
-- ١) الظهور — مباشر، بلا طلب (هي صاحبة القرار)
-- ─────────────────────────────────────────────────────────────
create or replace function public.women_family_set_visibility(
  p_self boolean default null, p_spouse boolean default null, p_children boolean default null)
returns jsonb
language plpgsql security definer set search_path to 'public'
as $function$
declare
  me uuid := public.my_active_women_node();
  w  public.women_members%rowtype;
begin
  if me is null then
    raise exception 'الحساب غير مفعّل أو غير مربوط بالشجرة' using errcode = '42501', hint = 'no_node';
  end if;
  select * into w from public.women_members where id = me for update;
  if lower(coalesce(w.gender, '')) <> 'female' then
    raise exception 'هذا الخيار للبنات' using errcode = '42501', hint = 'not_female_node';
  end if;
  update public.women_members
     set is_hidden_from_tree = case when p_self is null then is_hidden_from_tree else not p_self end,
         spouse_shown        = coalesce(p_spouse, spouse_shown),
         children_shown      = coalesce(p_children, children_shown)
   where id = me
  returning * into w;
  return jsonb_build_object('self', not coalesce(w.is_hidden_from_tree, false),
                            'spouse', coalesce(w.spouse_shown, false),
                            'children', coalesce(w.children_shown, false),
                            'hidden_children', coalesce(to_jsonb(w.hidden_children), '[]'::jsonb));
end $function$;

create or replace function public.women_family_set_child_visible(p_child_id uuid, p_visible boolean)
returns void
language plpgsql security definer set search_path to 'public'
as $function$
declare me uuid := public.my_active_women_node();
begin
  if me is null then
    raise exception 'الحساب غير مفعّل أو غير مربوط بالشجرة' using errcode = '42501', hint = 'no_node';
  end if;
  if not exists (select 1 from public.women_members c where c.id = p_child_id and c.mother_id = me) then
    raise exception 'هذا الاسم ليس من الأبناء' using errcode = '42501', hint = 'not_your_child';
  end if;
  update public.women_members
     set hidden_children = case
           when coalesce(p_visible, true)
             then nullif(array_remove(coalesce(hidden_children, '{}'), p_child_id), '{}')
           else (select array_agg(distinct x) from unnest(coalesce(hidden_children, '{}') || p_child_id) x)
         end
   where id = me;
end $function$;

-- ترتيب عيالها (من زوج من خارج العائلة) — «ترتيب» في «عائلتي»
create or replace function public.women_family_reorder_children(p_ids uuid[])
returns void
language plpgsql security definer set search_path to 'public'
as $function$
declare me uuid := public.my_active_women_node(); i int;
begin
  if me is null then
    raise exception 'الحساب غير مفعّل أو غير مربوط بالشجرة' using errcode = '42501', hint = 'no_node';
  end if;
  for i in 1 .. coalesce(array_length(p_ids, 1), 0) loop
    update public.women_members c set sort_order = i - 1
     where c.id = p_ids[i] and c.mother_id = me
       and exists (select 1 from public.women_members h where h.id = c.parent_id and coalesce(h.is_outside_family, false));
  end loop;
end $function$;

-- ─────────────────────────────────────────────────────────────
-- ٢) إضافة الزوج — من العائلة (رجل في الشجرة) أو من خارجها (بالاسم)
-- ─────────────────────────────────────────────────────────────
create or replace function private.women_family_set_husband_direct(
  p_family_id uuid, p_name text, p_deceased boolean, p_visible boolean)
returns uuid
language plpgsql security definer set search_path to 'public'
as $function$
declare
  me  uuid := public.my_active_women_node();
  w   public.women_members%rowtype;
  h   public.women_members%rowtype;
  nm  text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  hid uuid;
begin
  if me is null then
    raise exception 'الحساب غير مفعّل أو غير مربوط بالشجرة' using errcode = '42501', hint = 'no_node';
  end if;
  select * into w from public.women_members where id = me for update;
  if lower(coalesce(w.gender, '')) <> 'female' then
    raise exception 'هذا الخيار للبنات' using errcode = '42501', hint = 'not_female_node';
  end if;
  if w.husband_id is not null then
    raise exception 'يوجد زوج مسجّل، والتعديل عن طريق الإدارة' using errcode = 'P0001', hint = 'has_husband';
  end if;
  if p_family_id is not null then
    select * into h from public.women_members where id = p_family_id;
    if not found or lower(coalesce(h.gender, 'male')) <> 'male' or coalesce(h.is_outside_family, false)
       or h.id = w.parent_id then
      raise exception 'يرجى اختيار الزوج من الشجرة' using errcode = 'P0001', hint = 'not_family_man';
    end if;
    hid := h.id;
  else
    if nm = '' then
      raise exception 'يرجى كتابة اسم الزوج' using errcode = '22023', hint = 'name_required';
    end if;
    if length(nm) > 120 then
      raise exception 'الاسم طويل' using errcode = '22023', hint = 'name_too_long';
    end if;
    insert into public.women_members (id, first_name, full_name, gender, parent_id, is_married, is_deceased,
                                      is_outside_family, sort_order)
    values (gen_random_uuid(), split_part(nm, ' ', 1), nm, 'male', null, true, coalesce(p_deceased, false), true, 0)
    returning id into hid;
  end if;
  update public.women_members
     set husband_id = hid, is_married = true, spouse_shown = coalesce(p_visible, false)
   where id = me;
  return hid;
end $function$;

-- ─────────────────────────────────────────────────────────────
-- ٣) إضافة ابن/بنت — لزوج من خارج العائلة فقط (عيال الزوج من العائلة تحت أبيهم في شجرة العائلة)
--    الاسم في الشجرة = الاسم الأول + اسم الزوج
-- ─────────────────────────────────────────────────────────────
create or replace function private.women_family_add_child_direct(
  p_first_name text, p_female boolean, p_birth date, p_deceased boolean)
returns uuid
language plpgsql security definer set search_path to 'public'
as $function$
declare
  me  uuid := public.my_active_women_node();
  w   public.women_members%rowtype;
  h   public.women_members%rowtype;
  nm  text := btrim(regexp_replace(coalesce(p_first_name, ''), '\s+', ' ', 'g'));
  cid uuid;
begin
  if me is null then
    raise exception 'الحساب غير مفعّل أو غير مربوط بالشجرة' using errcode = '42501', hint = 'no_node';
  end if;
  select * into w from public.women_members where id = me;
  if lower(coalesce(w.gender, '')) <> 'female' then
    raise exception 'هذا الخيار للبنات' using errcode = '42501', hint = 'not_female_node';
  end if;
  if w.husband_id is null then
    raise exception 'يجب إضافة الزوج أولاً' using errcode = 'P0001', hint = 'need_husband';
  end if;
  select * into h from public.women_members where id = w.husband_id;
  if not coalesce(h.is_outside_family, false) then
    raise exception 'الأبناء من زوج من العائلة يظهرون تحت أبيهم في شجرة العائلة' using errcode = 'P0001', hint = 'family_husband';
  end if;
  if nm = '' then
    raise exception 'يرجى كتابة الاسم' using errcode = '22023', hint = 'name_required';
  end if;
  if length(nm) > 60 then
    raise exception 'الاسم طويل' using errcode = '22023', hint = 'name_too_long';
  end if;
  if p_birth is not null and p_birth > current_date then
    raise exception 'تاريخ الميلاد في المستقبل' using errcode = '22023', hint = 'bad_birth';
  end if;
  insert into public.women_members (id, first_name, full_name, parent_id, mother_id, gender, sort_order,
                                    birth_date, is_deceased)
  values (gen_random_uuid(), nm,
          btrim(nm || ' ' || coalesce(nullif(btrim(h.full_name), ''), btrim(coalesce(h.first_name, '')))),
          h.id, me, case when coalesce(p_female, false) then 'female' else 'male' end,
          coalesce((select max(c.sort_order) + 1 from public.women_members c where c.parent_id = h.id), 0),
          p_birth, coalesce(p_deceased, false))
  returning id into cid;
  return cid;
end $function$;

-- الواجهتان العامتان: مباشر للإدارة أو متى ما أُطفئت الموافقة، وإلا تجربة جافة ثم طلب «إضافة قريب»
create or replace function public.women_family_set_husband(
  p_family_id uuid default null, p_name text default null, p_deceased boolean default false, p_visible boolean default false)
returns uuid
language plpgsql security definer set search_path to 'public'
as $function$
declare nm text;
begin
  if not private.self_relative_needs_request() then
    return private.women_family_set_husband_direct(p_family_id, p_name, p_deceased, p_visible);
  end if;
  begin
    perform private.women_family_set_husband_direct(p_family_id, p_name, p_deceased, p_visible);
    raise exception 'dry_run' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  nm := coalesce(nullif(btrim(coalesce(p_name, '')), ''),
                 (select w.full_name from public.women_members w where w.id = p_family_id));
  perform private.self_relative_request('women_family_set_husband',
    jsonb_build_object('p_family_id', p_family_id, 'p_name', nullif(btrim(coalesce(p_name, '')), ''),
                       'p_deceased', coalesce(p_deceased, false), 'p_visible', coalesce(p_visible, false)),
    'husband', nm);
  return null;
end $function$;

create or replace function public.women_family_add_child(
  p_first_name text, p_female boolean default false, p_birth date default null, p_deceased boolean default false)
returns uuid
language plpgsql security definer set search_path to 'public'
as $function$
begin
  if not private.self_relative_needs_request() then
    return private.women_family_add_child_direct(p_first_name, p_female, p_birth, p_deceased);
  end if;
  begin
    perform private.women_family_add_child_direct(p_first_name, p_female, p_birth, p_deceased);
    raise exception 'dry_run' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform private.self_relative_request('women_family_add_child',
    jsonb_build_object('p_first_name', btrim(coalesce(p_first_name, '')), 'p_female', coalesce(p_female, false),
                       'p_birth', p_birth, 'p_deceased', coalesce(p_deceased, false)),
    case when coalesce(p_female, false) then 'daughter' else 'son' end, btrim(coalesce(p_first_name, '')));
  return null;
end $function$;

-- مسمّيات الطلب الجديدة في «إضافة قريبة»
create or replace function private.self_relative_request(p_rpc text, p_args jsonb, p_kind text, p_name text)
returns void
language plpgsql security definer set search_path to 'public'
as $function$
declare
  me      uuid := public.current_profile_id();
  payload jsonb;
  k_label text := case p_kind when 'wife' then 'زوجة' when 'mother' then 'أم' when 'sister' then 'أخت'
                              when 'husband' then 'زوج' when 'son' then 'ابن' when 'daughter' then 'بنت'
                              else 'قريبة' end;
begin
  payload := jsonb_build_object('v', 1, 'rpc', p_rpc, 'args', p_args, 'kind', p_kind,
                                'name', nullif(btrim(coalesce(p_name, '')), ''),
                                'requester_id', me,
                                'summary', 'إضافة ' || k_label || coalesce(': ' || nullif(btrim(coalesce(p_name, '')), ''), ''));
  if exists (select 1 from public.admin_requests r
              where r.request_type = 'relative_add' and r.status = 'pending' and r.requester_id = me
                and r.details::jsonb -> 'rpc' = payload -> 'rpc' and r.details::jsonb -> 'args' = payload -> 'args') then
    return;
  end if;
  perform set_config('app.self_relative_rpc', 'on', true);
  insert into public.admin_requests (member_id, requester_id, request_type, status, details, new_value)
  values (me, me, 'relative_add', 'pending', payload::text, p_kind);
  perform set_config('app.self_relative_rpc', '', true);
end $function$;


-- الموافقة على «إضافة قريبة» تنفّذ الدالتين الجديدتين أيضاً — ترقيع الدالة الحيّة (20261113130000) لا استبدالها
do $mig$
declare
  src text := pg_get_functiondef('public.decide_admin_request(uuid,text,text,jsonb)'::regprocedure);
  anchor_a text := $a$v_rpc not in ('add_self_wife', 'add_self_mother', 'add_or_link_self_relative'))$a$;
  patch_a  text := $a$v_rpc not in ('add_self_wife', 'add_self_mother', 'add_or_link_self_relative',
                                     'women_family_set_husband', 'women_family_add_child'))$a$;
  anchor_b text := $b$    elsif v_rpc = 'add_self_mother' then
      new_id := private.add_self_mother_direct(a ->> 'p_name');
    else$b$;
  patch_b  text := $b$    elsif v_rpc = 'add_self_mother' then
      new_id := private.add_self_mother_direct(a ->> 'p_name');
    elsif v_rpc = 'women_family_set_husband' then
      new_id := private.women_family_set_husband_direct((a ->> 'p_family_id')::uuid, a ->> 'p_name',
                                                        coalesce((a ->> 'p_deceased')::boolean, false),
                                                        coalesce((a ->> 'p_visible')::boolean, false));
    elsif v_rpc = 'women_family_add_child' then
      new_id := private.women_family_add_child_direct(a ->> 'p_first_name', coalesce((a ->> 'p_female')::boolean, false),
                                                      (a ->> 'p_birth')::date, coalesce((a ->> 'p_deceased')::boolean, false));
    else$b$;
begin
  if position('women_family_set_husband' in src) > 0 then
    return;  -- مطبَّق
  end if;
  if position(anchor_a in src) = 0 or position(anchor_b in src) = 0 then
    raise exception 'decide_admin_request anchors not found — function changed, update this migration';
  end if;
  execute replace(replace(src, anchor_a, patch_a), anchor_b, patch_b);
end
$mig$;

revoke all on function public.women_family_set_visibility(boolean, boolean, boolean) from public, anon;
revoke all on function public.women_family_set_child_visible(uuid, boolean) from public, anon;
revoke all on function public.women_family_reorder_children(uuid[]) from public, anon;
revoke all on function public.women_family_set_husband(uuid, text, boolean, boolean) from public, anon;
revoke all on function public.women_family_add_child(text, boolean, date, boolean) from public, anon;
grant execute on function public.women_family_set_visibility(boolean, boolean, boolean) to authenticated;
grant execute on function public.women_family_set_child_visible(uuid, boolean) to authenticated;
grant execute on function public.women_family_reorder_children(uuid[]) to authenticated;
grant execute on function public.women_family_set_husband(uuid, text, boolean, boolean) to authenticated;
grant execute on function public.women_family_add_child(text, boolean, date, boolean) to authenticated;
revoke all on function private.women_family_set_husband_direct(uuid, text, boolean, boolean) from public, anon, authenticated;
revoke all on function private.women_family_add_child_direct(text, boolean, date, boolean) from public, anon, authenticated;
