-- «عائلتي» عند البنت + «ما يظهر في الشجرة» (طلب المالك ٢٠٢٦-١١-٠٩، «ممتاز ابدء»)
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

-- الموافقة على «إضافة قريبة» تنفّذ الدالتين الجديدتين أيضاً (بقية الدالة كما هي حرفياً)
create or replace function public.decide_admin_request(p_request_id uuid, p_decision text, p_reason text default null::text, p_overrides jsonb default null::jsonb)
returns jsonb
language plpgsql security definer set search_path to 'public'
as $function$
declare
  uid       uuid := auth.uid();
  me        uuid := public.current_profile_id();
  my_role   text := coalesce(public.current_user_role(), 'pending');
  r         public.admin_requests%rowtype;
  decision  text := lower(btrim(coalesce(p_decision, '')));
  approving boolean;
  reason    text := nullif(regexp_replace(coalesce(p_reason, ''), '^\s+|\s+$', '', 'g'), '');
  d         jsonb;
  a         jsonb;
  req_auth  uuid;
  saved     text;
  new_id    uuid;
  summary   text;
  notified  boolean := false;
begin
  select * into r from public.admin_requests where id = p_request_id;
  if not found or r.request_type is distinct from 'relative_add' then
    return private.decide_admin_request_core(p_request_id, p_decision, p_reason, p_overrides);
  end if;
  if uid is null or me is null then
    raise exception 'not_authenticated' using errcode = '42501', hint = 'not_authenticated';
  end if;
  if decision not in ('approve', 'reject') then
    raise exception 'bad_decision' using errcode = '22023', hint = 'bad_decision';
  end if;
  if p_overrides is not null and p_overrides <> '{}'::jsonb then
    raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload', detail = 'overrides';
  end if;
  approving := decision = 'approve';
  select * into r from public.admin_requests where id = p_request_id for update;
  if not public.can_handle_admin_request(r.request_type) then
    raise exception 'not_allowed' using errcode = '42501', hint = 'not_allowed';
  end if;
  if my_role <> 'owner' and (r.requester_id = any (array[uid, me]) or r.member_id = any (array[uid, me])) then
    raise exception 'own_request' using errcode = '42501', hint = 'own_request';
  end if;
  if r.status is distinct from 'pending' then
    raise exception 'already_handled' using errcode = 'P0001', hint = 'already_handled';
  end if;
  begin
    d := r.details::jsonb;
  exception when others then
    d := null;
  end;
  if d is null or jsonb_typeof(d) <> 'object' or jsonb_typeof(d->'args') is distinct from 'object'
     or coalesce(d->>'rpc', '') not in ('add_self_wife', 'add_self_mother', 'add_or_link_self_relative',
                                        'women_family_set_husband', 'women_family_add_child') then
    raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload', detail = 'details';
  end if;
  a := d->'args';
  summary := coalesce(d->>'summary', 'إضافة قريبة');
  if approving then
    req_auth := public.account_auth_id(r.requester_id);
    if req_auth is null then
      raise exception 'صاحب الطلب لم يعد له حساب' using errcode = 'P0001', hint = 'requester_gone';
    end if;
    saved := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims',
      json_build_object('sub', req_auth, 'role', 'authenticated',
                        'app_metadata', json_build_object('profile_id', r.requester_id))::text, true);
    if d->>'rpc' = 'add_self_wife' then
      new_id := private.add_self_wife_direct(a->>'p_name', coalesce((a->>'p_hidden')::boolean, false));
    elsif d->>'rpc' = 'add_self_mother' then
      new_id := private.add_self_mother_direct(a->>'p_name');
    elsif d->>'rpc' = 'women_family_set_husband' then
      new_id := private.women_family_set_husband_direct((a->>'p_family_id')::uuid, a->>'p_name',
                                                        coalesce((a->>'p_deceased')::boolean, false),
                                                        coalesce((a->>'p_visible')::boolean, false));
    elsif d->>'rpc' = 'women_family_add_child' then
      new_id := private.women_family_add_child_direct(a->>'p_first_name', coalesce((a->>'p_female')::boolean, false),
                                                      (a->>'p_birth')::date, coalesce((a->>'p_deceased')::boolean, false));
    else
      new_id := private.add_or_link_self_relative_direct(a->>'p_kind', (a->>'p_father_id')::uuid,
                                                         (a->>'p_woman_id')::uuid, a->>'p_name');
    end if;
    perform set_config('request.jwt.claims', coalesce(saved, ''), true);
  end if;
  update public.admin_requests set status = case when approving then 'approved' else 'rejected' end where id = r.id;
  if my_role in ('owner', 'admin') and r.requester_id is not null
     and exists (select 1 from public.profiles p where p.id = r.requester_id) then
    insert into public.notifications (target_member_id, title, body, kind, created_by)
    values (r.requester_id,
            case when approving then 'تم قبول طلبك' else 'لم يتم قبول طلبك' end,
            case when approving then 'تمت الموافقة: ' || summary
                 else 'تم رفض طلب ' || summary || coalesce(E'\nالسبب: ' || reason, '') end,
            case when approving then 'admin' else 'request_rejected' end, me);
    notified := true;
  end if;
  return jsonb_build_object('ok', true, 'request_id', r.id, 'request_type', r.request_type,
    'status', case when approving then 'approved' else 'rejected' end, 'action', d->>'rpc',
    'requester_notified', notified, 'admin_push', null, 'death_announcement', null,
    'storage_cleanup', null, 'new_member_id', new_id);
end $function$;

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
