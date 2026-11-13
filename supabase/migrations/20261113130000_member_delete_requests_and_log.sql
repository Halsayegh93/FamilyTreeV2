-- طلب المالك ٢٠٢٦-١١-١٣: «نعم طبّق … عطني إشعار بالإدارة وورني المعاينة، وأي شخص يُحذف يصلني طلب من الأعضاء،
-- والإدارة ما يصل طلب بس إشعار ومنجز».
--  ١) سجلّ مكان المحذوف `member_delete_log` (أبوه، أمّه، زوجها، ترتيبه، من حذف ومتى، وطلبه إن وُجد) — يُقرأ عبر
--     `member_delete_places()` للمالك والمدير والمراقب فقط، ويستبعد «النقل» (adopt، تغيير الجنس، دمج الزوجة المكرّرة).
--  ٢) حذف العضو من «عائلتي» (ابن/بنت في الشجرة، بنت أو زوجة في شجرة النساء) = طلب `relative_remove` بانتظار المالك
--     أو المدير — نفس نمط «إضافة قريبة» (تجربة بلا حذف للفحص، ثم طلب، والموافقة تعيد تنفيذ الدالة باسم صاحبه).
--     سحب «إضافة ابن» المعلّق لصاحبه يبقى حذفاً مباشراً. الإدارة (is_team) تحذف مباشرة كما كانت → إشعار + «المنجزة».
--     المفتاح من السيرفر: app_config `self_remove_requires_approval` (الافتراضي مفعّل).
--  ٣) طلب «تعديل الشجرة — حذف» يبقى بعد تنفيذه (كان يُحذف معه بـ CASCADE على member_id): يُنقل member_id لصاحبه.
-- التراجع: supabase/rollback/20261113130000_member_delete_requests_and_log_rollback.sql

-- ═══ ١) السجلّ ═══
create table if not exists public.member_delete_log (
  id              bigint generated always as identity primary key,
  member_id       uuid not null,
  tree            text not null check (tree in ('main', 'women')),
  first_name      text,
  full_name       text,
  gender          text,
  parent_id       uuid,
  mother_id       uuid,
  husband_id      uuid,
  sort_order      numeric,
  birth_date      text,
  is_deceased     boolean,
  avatar_url      text,
  deleted_by      uuid,
  deleted_by_role text,
  request_id      uuid,
  deleted_at      timestamptz not null default now()
);
create index if not exists member_delete_log_member_idx on public.member_delete_log (member_id);
create index if not exists member_delete_log_time_idx on public.member_delete_log (deleted_at desc);
alter table public.member_delete_log enable row level security;
-- بلا سياسات: لا قراءة ولا كتابة مباشرة من التطبيقات — القراءة عبر member_delete_places() فقط
revoke all on public.member_delete_log from public, anon, authenticated;

create or replace function private.log_member_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  o     jsonb := to_jsonb(old);
  women boolean := tg_table_name = 'women_members';
  rid   text := nullif(current_setting('family.delete_request', true), '');
begin
  -- «ربط بالشجرة» نقل سجل لا حذف
  if coalesce(current_setting('family.merging', true), '') = 'on' then return null; end if;
  -- مرايا الرجال في شجرة النساء تُحذف مع ملفاتهم — السجل للنساء فقط
  if women and coalesce(lower(o ->> 'gender'), 'female') <> 'female' then return null; end if;
  -- طلب انضمام مرفوض ليس من الشجرة
  if not women and coalesce(o ->> 'role', '') = 'pending' then return null; end if;
  insert into public.member_delete_log (member_id, tree, first_name, full_name, gender, parent_id, mother_id,
                                        husband_id, sort_order, birth_date, is_deceased, avatar_url,
                                        deleted_by, deleted_by_role, request_id)
  values ((o ->> 'id')::uuid,
          case when women then 'women' else 'main' end,
          o ->> 'first_name', o ->> 'full_name', o ->> 'gender',
          nullif(coalesce(o ->> 'father_id', o ->> 'parent_id'), '')::uuid,
          nullif(o ->> 'mother_id', '')::uuid,
          nullif(o ->> 'husband_id', '')::uuid,
          case when (o ->> 'sort_order') ~ '^-?[0-9]+(\.[0-9]+)?$' then (o ->> 'sort_order')::numeric end,
          o ->> 'birth_date',
          coalesce((o ->> 'is_deceased')::boolean, false),
          coalesce(nullif(o ->> 'avatar_url', ''), nullif(o ->> 'photo_url', '')),
          public.current_profile_id(), public.current_user_role(),
          case when rid ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then rid::uuid end);
  return null;
end
$$;
revoke all on function private.log_member_delete() from public, anon, authenticated;

drop trigger if exists trg_zzzz_log_member_delete on public.profiles;
create trigger trg_zzzz_log_member_delete after delete on public.profiles
  for each row execute function private.log_member_delete();
drop trigger if exists trg_zzzz_log_member_delete on public.women_members;
create trigger trg_zzzz_log_member_delete after delete on public.women_members
  for each row execute function private.log_member_delete();

-- القراءة: المالك والمدير والمراقب. يستبعد ما لم يُحذف فعلاً (المعرّف موجود) وما نُقل لسجلّ جديد بالاسم نفسه
-- (adopt_tree_profile: نسخة بالاسم والأب خلال دقيقتين · move_child_gender ودمج الزوجة المكرّرة: عقدة نساء بالاسم والأب/الزوج)
create or replace function public.member_delete_places(p_ids uuid[] default null, p_since timestamptz default null,
                                                       p_limit int default 200)
returns table (member_id uuid, tree text, first_name text, full_name text, gender text, parent_id uuid,
               parent_name text, mother_id uuid, husband_id uuid, sort_order numeric, birth_date text,
               is_deceased boolean, avatar_url text, deleted_by uuid, deleted_by_name text, deleted_by_role text,
               request_id uuid, deleted_at timestamptz)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if coalesce(public.current_user_role(), '') not in ('owner', 'admin', 'monitor') then
    raise exception 'not_allowed' using errcode = '42501', hint = 'not_allowed';
  end if;
  return query
  select l.member_id, l.tree, l.first_name, l.full_name, l.gender, l.parent_id,
         public.notif_short_name(l.parent_id), l.mother_id, l.husband_id, l.sort_order, l.birth_date,
         l.is_deceased, l.avatar_url, l.deleted_by, public.notif_short_name(l.deleted_by), l.deleted_by_role,
         l.request_id, l.deleted_at
    from public.member_delete_log l
   where (p_ids is null or l.member_id = any (p_ids))
     and (p_since is null or l.deleted_at >= p_since)
     and not exists (select 1 from public.profiles p where p.id = l.member_id)
     and not exists (select 1 from public.women_members w where w.id = l.member_id)
     and not exists (select 1 from public.profiles p
                      where l.tree = 'main'
                        and p.full_name is not distinct from l.full_name
                        and p.father_id is not distinct from l.parent_id
                        and p.created_at between l.deleted_at - interval '2 minutes' and l.deleted_at + interval '2 minutes')
     and not exists (select 1 from public.women_members w
                      where w.full_name is not distinct from l.full_name
                        and ((l.parent_id is not null and w.parent_id = l.parent_id)
                             or (l.husband_id is not null and w.husband_id = l.husband_id)))
   order by l.deleted_at desc
   limit greatest(1, least(coalesce(p_limit, 200), 500));
end
$$;
revoke execute on function public.member_delete_places(uuid[], timestamptz, int) from public, anon;
grant execute on function public.member_delete_places(uuid[], timestamptz, int) to authenticated, service_role;

-- ═══ ٣) طلب «تعديل الشجرة — حذف» يبقى بعد تنفيذه ═══
create or replace function private.keep_delete_requests()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.admin_requests r
     set member_id = r.requester_id
   where r.member_id = old.id
     and r.request_type = 'tree_edit'
     and coalesce(r.new_value, '') in ('delete', 'حذف')
     and r.requester_id is not null
     and r.requester_id <> old.id
     and exists (select 1 from public.profiles p where p.id = r.requester_id);
  return old;
end
$$;
revoke all on function private.keep_delete_requests() from public, anon, authenticated;
drop trigger if exists trg_aaa_keep_delete_requests on public.profiles;
create trigger trg_aaa_keep_delete_requests before delete on public.profiles
  for each row execute function private.keep_delete_requests();

-- ═══ ٢) حذف العضو من «عائلتي» = طلب ═══
-- الدوال الأصلية كما هي في private (التنفيذ الفعلي)، وإشعار «حذف ابن» القديم لا يُرسل حين تنفّذها الموافقة
create or replace function private.remove_self_child_direct(p_child_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  me       uuid := public.current_profile_id();
  my_role  text := coalesce(public.current_user_role(), '');
  c        public.profiles%rowtype;
  me_first text;
  c_first  text;
  v_msg    text;
  v_hint   text;
begin
  if me is null or my_role not in ('member', 'supervisor', 'monitor', 'admin', 'owner') then
    raise exception 'لا يمكنك حذف الأبناء — حسابك غير مفعّل'
      using errcode = '42501', hint = 'not_allowed';
  end if;
  select * into c from public.profiles where id = p_child_id for update;
  if not found or c.father_id is distinct from me or c.id = me then
    raise exception 'هذا الابن ليس من أبنائك'
      using errcode = '42501', hint = 'not_your_child';
  end if;
  if exists (select 1 from auth.users u
              where u.id = c.id or (u.raw_app_meta_data ->> 'profile_id') = c.id::text) then
    raise exception 'لهذا الابن حساب دخول — يحذفه المالك أو المدير'
      using errcode = '42501', hint = 'has_account';
  end if;
  if coalesce(c.is_deceased, false) and my_role not in ('owner', 'admin') then
    raise exception 'سجل متوفى — يحذفه المالك أو المدير'
      using errcode = '42501', hint = 'deceased_protected';
  end if;
  me_first := coalesce((select nullif(btrim(p.first_name), '') from public.profiles p where p.id = me), 'عضو');
  c_first  := coalesce(nullif(btrim(c.first_name), ''), nullif(split_part(btrim(coalesce(c.full_name, '')), ' ', 1), ''), 'الابن');
  delete from public.admin_requests
   where request_type = 'child_add'
     and status = 'pending'
     and lower(btrim(coalesce(new_value, ''))) = lower(c.id::text);
  begin
    delete from public.profiles where id = c.id;
  exception when foreign_key_violation then
    get stacked diagnostics v_msg = message_text, v_hint = pg_exception_hint;
    if v_hint = 'family_links_protected' then
      raise exception using message = v_msg, errcode = '23503', hint = 'family_links_protected';
    end if;
    raise;
  end;
  if coalesce(current_setting('app.self_remove_exec', true), '') <> 'on' then
    insert into public.notifications (target_member_id, title, body, kind, created_by)
    select p.id, 'حذف ابن من الشجرة', me_first || ' حذف ابنه «' || c_first || '» من الشجرة',
           'admin_edit_child_remove', me
      from public.profiles p
     where p.role in ('owner', 'admin')
       and p.status = 'active'
       and p.id <> me;
  end if;
  return jsonb_build_object('deleted', true, 'id', c.id);
end
$$;

create or replace function private.remove_self_wife_direct(p_wife_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := public.my_active_women_node();
begin
  if me is null then
    raise exception 'no_node';
  end if;
  -- لازم تكون زوجة المستخدم فعلاً
  if not exists (
    select 1 from public.women_members where id = p_wife_id and husband_id = me
  ) then
    raise exception 'not_your_wife';
  end if;

  -- فكّ الارتباط أولاً
  update public.women_members set husband_id = null where id = p_wife_id;

  -- إذا صارت بلا أي روابط (أب/أم/حساب) وبلا أبناء يشيرون لها → احذفها
  if not exists (
        select 1 from public.women_members
        where id = p_wife_id
          and (parent_id is not null or mother_id is not null or linked_user_id is not null)
      )
     and not exists (
        select 1 from public.women_members c
        where c.parent_id = p_wife_id or c.mother_id = p_wife_id
      ) then
    delete from public.women_members where id = p_wife_id;
  end if;
end
$$;

create or replace function private.remove_self_woman_child_direct(p_child_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := public.my_active_women_node();
  c public.women_members%rowtype;
begin
  if me is null then raise exception 'no_node'; end if;
  select * into c from public.women_members where id = p_child_id and parent_id = me;
  if not found then
    raise exception 'not_your_child';
  end if;
  -- لها حساب دخول — ملف عضوة حقيقي لا يحذفه الأب
  if c.linked_user_id is not null then
    raise exception 'لهذه البنت حساب — يحذفها المالك أو المدير' using errcode = '42501', hint = 'has_account';
  end if;
  -- المتوفاة سجلّ نسب — للمالك والمدير فقط
  if coalesce(c.is_deceased, false) and coalesce(public.current_user_role(), '') not in ('owner', 'admin') then
    raise exception 'سجل متوفاة — يحذفها المالك أو المدير' using errcode = '42501', hint = 'deceased_protected';
  end if;
  delete from public.women_members where id = p_child_id;
end
$$;

create or replace function private.self_remove_needs_request()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select not public.is_team(auth.uid())
     and coalesce(current_setting('app.self_remove_exec', true), '') <> 'on'
     and public.config_bool('self_remove_requires_approval', true);
$$;

-- الطلب + إشعار المالك والمدير (`admin_request` بمعرّف الطلب — «يحتاج إجراء» في «إشعارات الإدارة»)
create or replace function private.self_remove_request(p_rpc text, p_args jsonb, p_kind text, p_target uuid,
                                                       p_tree text, p_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  me       uuid := public.current_profile_id();
  nm       text := nullif(btrim(coalesce(p_name, '')), '');
  k_label  text := case p_kind when 'son' then 'ابن' when 'daughter' then 'بنت' when 'wife' then 'زوجة' else 'قريب' end;
  k_his    text := case p_kind when 'son' then 'ابنه' when 'daughter' then 'ابنته' when 'wife' then 'زوجته' else 'قريبه' end;
  payload  jsonb;
  rid      uuid;
  me_first text;
begin
  select r.id into rid from public.admin_requests r
   where r.request_type = 'relative_remove' and r.status = 'pending' and r.requester_id = me
     and r.details::jsonb -> 'rpc' = to_jsonb(p_rpc) and r.details::jsonb -> 'args' = p_args
   limit 1;
  if rid is not null then
    return rid;
  end if;
  payload := jsonb_build_object('v', 1, 'rpc', p_rpc, 'args', p_args, 'kind', p_kind, 'tree', p_tree,
                                'target_id', p_target, 'name', nm, 'requester_id', me,
                                'summary', 'حذف ' || k_label || coalesce(': ' || nm, ''));
  perform set_config('app.self_remove_rpc', 'on', true);
  insert into public.admin_requests (member_id, requester_id, request_type, status, details, new_value)
  values (me, me, 'relative_remove', 'pending', payload::text, p_target::text)
  returning id into rid;
  perform set_config('app.self_remove_rpc', '', true);
  me_first := coalesce((select nullif(btrim(p.first_name), '') from public.profiles p where p.id = me), 'عضو');
  insert into public.notifications (target_member_id, title, body, kind, created_by, request_id, request_type)
  select p.id, 'طلب حذف من الشجرة', me_first || ' يطلب حذف ' || k_his || coalesce(' «' || nm || '»', ''),
         'admin_request', me, rid, 'relative_remove'
    from public.profiles p
   where p.role in ('owner', 'admin') and p.status = 'active' and p.id <> me;
  return rid;
end
$$;
revoke all on function private.remove_self_child_direct(uuid) from public, anon, authenticated;
revoke all on function private.remove_self_wife_direct(uuid) from public, anon, authenticated;
revoke all on function private.remove_self_woman_child_direct(uuid) from public, anon, authenticated;
revoke all on function private.self_remove_needs_request() from public, anon, authenticated;
revoke all on function private.self_remove_request(text, jsonb, text, uuid, text, text) from public, anon, authenticated;

-- الواجهات العامة: الإدارة (أو المفتاح مطفأ) = حذف كما كان؛ العضو = فحص بلا حذف ثم طلب → {requested: true}
create or replace function public.remove_self_child(p_child_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c   public.profiles%rowtype;
  rid uuid;
begin
  if not private.self_remove_needs_request() then
    return private.remove_self_child_direct(p_child_id);
  end if;
  -- سحب «إضافة ابن» المعلّق لصاحبه: حذف مباشر كما كان
  if exists (select 1 from public.admin_requests r
              where r.request_type = 'child_add' and r.status = 'pending'
                and lower(btrim(coalesce(r.new_value, ''))) = lower(p_child_id::text)
                and r.requester_id = public.current_profile_id()) then
    return private.remove_self_child_direct(p_child_id);
  end if;
  begin
    perform private.remove_self_child_direct(p_child_id);
    raise exception 'dry_run' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  select * into c from public.profiles where id = p_child_id;
  rid := private.self_remove_request('remove_self_child', jsonb_build_object('p_child_id', p_child_id),
           case when lower(coalesce(c.gender, '')) = 'female' then 'daughter' else 'son' end,
           p_child_id, 'main', coalesce(nullif(btrim(c.full_name), ''), c.first_name));
  return jsonb_build_object('requested', true, 'request_id', rid, 'id', p_child_id);
end
$$;

drop function if exists public.remove_self_wife(uuid);
create function public.remove_self_wife(p_wife_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  nm  text;
  rid uuid;
begin
  if not private.self_remove_needs_request() then
    perform private.remove_self_wife_direct(p_wife_id);
    return jsonb_build_object('deleted', true, 'id', p_wife_id);
  end if;
  begin
    perform private.remove_self_wife_direct(p_wife_id);
    raise exception 'dry_run' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  select coalesce(nullif(btrim(w.full_name), ''), w.first_name) into nm from public.women_members w where w.id = p_wife_id;
  rid := private.self_remove_request('remove_self_wife', jsonb_build_object('p_wife_id', p_wife_id),
                                     'wife', p_wife_id, 'women', nm);
  return jsonb_build_object('requested', true, 'request_id', rid, 'id', p_wife_id);
end
$$;

drop function if exists public.remove_self_woman_child(uuid);
create function public.remove_self_woman_child(p_child_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  nm  text;
  rid uuid;
begin
  if not private.self_remove_needs_request() then
    perform private.remove_self_woman_child_direct(p_child_id);
    return jsonb_build_object('deleted', true, 'id', p_child_id);
  end if;
  begin
    perform private.remove_self_woman_child_direct(p_child_id);
    raise exception 'dry_run' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  select coalesce(nullif(btrim(w.full_name), ''), w.first_name) into nm from public.women_members w where w.id = p_child_id;
  rid := private.self_remove_request('remove_self_woman_child', jsonb_build_object('p_child_id', p_child_id),
                                     'daughter', p_child_id, 'women', nm);
  return jsonb_build_object('requested', true, 'request_id', rid, 'id', p_child_id);
end
$$;
revoke execute on function public.remove_self_child(uuid) from public, anon;
revoke execute on function public.remove_self_wife(uuid) from public, anon;
revoke execute on function public.remove_self_woman_child(uuid) from public, anon;
grant execute on function public.remove_self_child(uuid) to authenticated, service_role;
grant execute on function public.remove_self_wife(uuid) to authenticated, service_role;
grant execute on function public.remove_self_woman_child(uuid) to authenticated, service_role;

-- القرار: نفس فرع «إضافة قريبة» — الموافقة تنفّذ الدالة باسم صاحب الطلب، ويُسجَّل الطلب على الحذف
create or replace function public.decide_admin_request(p_request_id uuid, p_decision text, p_reason text default null,
                                                       p_overrides jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
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
  is_remove boolean;
  v_rpc     text;
begin
  select * into r from public.admin_requests where id = p_request_id;
  if not found or r.request_type not in ('relative_add', 'relative_remove') then
    return private.decide_admin_request_core(p_request_id, p_decision, p_reason, p_overrides);
  end if;
  is_remove := r.request_type = 'relative_remove';
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
  v_rpc := coalesce(d ->> 'rpc', '');
  if d is null or jsonb_typeof(d) <> 'object' or jsonb_typeof(d -> 'args') is distinct from 'object'
     or (not is_remove and v_rpc not in ('add_self_wife', 'add_self_mother', 'add_or_link_self_relative'))
     or (is_remove and v_rpc not in ('remove_self_child', 'remove_self_wife', 'remove_self_woman_child')) then
    raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload', detail = 'details';
  end if;
  a := d -> 'args';
  summary := coalesce(d ->> 'summary', case when is_remove then 'حذف من الشجرة' else 'إضافة قريبة' end);
  if approving then
    req_auth := public.account_auth_id(r.requester_id);
    if req_auth is null then
      raise exception 'صاحب الطلب لم يعد له حساب' using errcode = 'P0001', hint = 'requester_gone';
    end if;
    saved := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims',
      json_build_object('sub', req_auth, 'role', 'authenticated',
                        'app_metadata', json_build_object('profile_id', r.requester_id))::text, true);
    if is_remove then
      perform set_config('app.self_remove_exec', 'on', true);
      perform set_config('family.delete_request', r.id::text, true);
      if v_rpc = 'remove_self_child' then
        perform private.remove_self_child_direct((a ->> 'p_child_id')::uuid);
      elsif v_rpc = 'remove_self_wife' then
        perform private.remove_self_wife_direct((a ->> 'p_wife_id')::uuid);
      else
        perform private.remove_self_woman_child_direct((a ->> 'p_child_id')::uuid);
      end if;
      perform set_config('app.self_remove_exec', '', true);
      perform set_config('family.delete_request', '', true);
    elsif v_rpc = 'add_self_wife' then
      new_id := private.add_self_wife_direct(a ->> 'p_name', coalesce((a ->> 'p_hidden')::boolean, false));
    elsif v_rpc = 'add_self_mother' then
      new_id := private.add_self_mother_direct(a ->> 'p_name');
    else
      new_id := private.add_or_link_self_relative_direct(a ->> 'p_kind', (a ->> 'p_father_id')::uuid,
                                                         (a ->> 'p_woman_id')::uuid, a ->> 'p_name');
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
    'status', case when approving then 'approved' else 'rejected' end, 'action', v_rpc,
    'requester_notified', notified, 'admin_push', null, 'death_announcement', null,
    'storage_cleanup', null, 'new_member_id', new_id);
end
$$;

-- الحارس والصلاحيات والمسار والتسمية: النوع الجديد (تعديل نصّي محدود على الدوال الحيّة — يفشل إن لم يجد النص)
do $$
declare
  src text;
  n   text;
begin
  -- الحارس: النوع مسموح، ولا يُنشئه إلا remove_self_*
  src := pg_get_functiondef('public.guard_admin_request_insert()'::regprocedure);
  n := replace(src, $q$'account_delete','privacy_request','relative_add','lineage_request') then$q$,
                    $q$'account_delete','privacy_request','relative_add','lineage_request','relative_remove') then$q$);
  if n = src then raise exception 'guard_admin_request_insert: type list not found'; end if;
  src := n;
  n := replace(src, $q$  -- «طلب النسب» تُنشئه$q$,
$q$  -- «طلب حذف من الشجرة» تُنشئه remove_self_child/remove_self_wife/remove_self_woman_child فقط (20261113130000)
  if new.request_type = 'relative_remove' and coalesce(current_setting('app.self_remove_rpc', true), '') <> 'on' then
    raise exception 'admin_request_type_not_allowed' using errcode = '42501';
  end if;
  -- «طلب النسب» تُنشئه$q$);
  if n = src then raise exception 'guard_admin_request_insert: lineage marker not found'; end if;
  execute n;

  -- الحذف للمالك والمدير فقط (canDeleteMembers) — المراقب لا يرى الطلب ولا يقرّره
  src := pg_get_functiondef('public.can_handle_admin_request(text)'::regprocedure);
  n := replace(src, $q$not in ('news_report', 'content_report', 'contact_message')$q$,
                    $q$not in ('news_report', 'content_report', 'contact_message', 'relative_remove')$q$);
  if n = src then raise exception 'can_handle_admin_request: monitor list not found'; end if;
  execute n;

  -- بلا «مختص»: قرار مباشر من المالك أو المدير (مثل الرسائل والنسب)
  src := pg_get_functiondef('public.workflow_specialist_role(text)'::regprocedure);
  n := replace(src, $q$when p_type in ('contact_message', 'lineage_request') then null$q$,
                    $q$when p_type in ('contact_message', 'lineage_request', 'relative_remove') then null$q$);
  if n = src then raise exception 'workflow_specialist_role: null list not found'; end if;
  execute n;

  src := pg_get_functiondef('public.admin_request_label(text)'::regprocedure);
  n := replace(src, $q$    when 'lineage_request'  then 'طلب النسب'$q$,
$q$    when 'lineage_request'  then 'طلب النسب'
    when 'relative_remove'  then 'طلب حذف من الشجرة'$q$);
  if n = src then raise exception 'admin_request_label: lineage line not found'; end if;
  execute n;
end
$$;
