-- التراجع عن 20261113130000: حذف العضو يرجع مباشراً كما كان، ويتوقف السجلّ والقراءة ونقل طلب «حذف».
-- جدول member_delete_log يبقى ببياناته (احذفه يدوياً إن أردت: drop table public.member_delete_log;).
-- طلبات relative_remove المعلّقة: ارفضها أو احذفها قبل التراجع (لا تُقرَّر بعده).

drop trigger if exists trg_zzzz_log_member_delete on public.profiles;
drop trigger if exists trg_zzzz_log_member_delete on public.women_members;
drop trigger if exists trg_aaa_keep_delete_requests on public.profiles;
drop function if exists public.member_delete_places(uuid[], timestamptz, int);

create or replace function public.remove_self_child(p_child_id uuid)
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
  insert into public.notifications (target_member_id, title, body, kind, created_by)
  select p.id, 'حذف ابن من الشجرة', me_first || ' حذف ابنه «' || c_first || '» من الشجرة',
         'admin_edit_child_remove', me
    from public.profiles p
   where p.role in ('owner', 'admin')
     and p.status = 'active'
     and p.id <> me;
  return jsonb_build_object('deleted', true, 'id', c.id);
end
$$;

drop function if exists public.remove_self_wife(uuid);
create function public.remove_self_wife(p_wife_id uuid)
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
  if not exists (
    select 1 from public.women_members where id = p_wife_id and husband_id = me
  ) then
    raise exception 'not_your_wife';
  end if;
  update public.women_members set husband_id = null where id = p_wife_id;
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

drop function if exists public.remove_self_woman_child(uuid);
create function public.remove_self_woman_child(p_child_id uuid)
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
  if c.linked_user_id is not null then
    raise exception 'لهذه البنت حساب — يحذفها المالك أو المدير' using errcode = '42501', hint = 'has_account';
  end if;
  if coalesce(c.is_deceased, false) and coalesce(public.current_user_role(), '') not in ('owner', 'admin') then
    raise exception 'سجل متوفاة — يحذفها المالك أو المدير' using errcode = '42501', hint = 'deceased_protected';
  end if;
  delete from public.women_members where id = p_child_id;
end
$$;
revoke execute on function public.remove_self_child(uuid) from public, anon;
revoke execute on function public.remove_self_wife(uuid) from public, anon;
revoke execute on function public.remove_self_woman_child(uuid) from public, anon;
grant execute on function public.remove_self_child(uuid) to authenticated, service_role;
grant execute on function public.remove_self_wife(uuid) to authenticated, service_role;
grant execute on function public.remove_self_woman_child(uuid) to authenticated, service_role;

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
     or coalesce(d->>'rpc', '') not in ('add_self_wife', 'add_self_mother', 'add_or_link_self_relative') then
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
end
$$;

do $$
declare
  src text;
  n   text;
begin
  src := pg_get_functiondef('public.guard_admin_request_insert()'::regprocedure);
  n := replace(src, $q$'account_delete','privacy_request','relative_add','lineage_request','relative_remove') then$q$,
                    $q$'account_delete','privacy_request','relative_add','lineage_request') then$q$);
  n := replace(n, $q$  -- «طلب حذف من الشجرة» تُنشئه remove_self_child/remove_self_wife/remove_self_woman_child فقط (20261113130000)
  if new.request_type = 'relative_remove' and coalesce(current_setting('app.self_remove_rpc', true), '') <> 'on' then
    raise exception 'admin_request_type_not_allowed' using errcode = '42501';
  end if;
$q$, '');
  execute n;

  src := pg_get_functiondef('public.can_handle_admin_request(text)'::regprocedure);
  execute replace(src, $q$not in ('news_report', 'content_report', 'contact_message', 'relative_remove')$q$,
                       $q$not in ('news_report', 'content_report', 'contact_message')$q$);

  src := pg_get_functiondef('public.workflow_specialist_role(text)'::regprocedure);
  execute replace(src, $q$when p_type in ('contact_message', 'lineage_request', 'relative_remove') then null$q$,
                       $q$when p_type in ('contact_message', 'lineage_request') then null$q$);

  src := pg_get_functiondef('public.admin_request_label(text)'::regprocedure);
  execute replace(src, $q$
    when 'relative_remove'  then 'طلب حذف من الشجرة'$q$, '');
end
$$;

drop function if exists private.self_remove_request(text, jsonb, text, uuid, text, text);
drop function if exists private.self_remove_needs_request();
drop function if exists private.remove_self_child_direct(uuid);
drop function if exists private.remove_self_wife_direct(uuid);
drop function if exists private.remove_self_woman_child_direct(uuid);
drop function if exists private.keep_delete_requests();
drop function if exists private.log_member_delete();
