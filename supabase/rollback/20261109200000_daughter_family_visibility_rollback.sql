-- تراجع 20261109200000_daughter_family_visibility — يعيد الدالتين كما كانتا حرفياً ويحذف الجديد
-- ملاحظة: الأزواج والعيال المضافون عبره يبقون صفوفاً عادية في women_members (لا حذف بيانات).
begin;
drop function if exists public.women_family_set_visibility(boolean, boolean, boolean);
drop function if exists public.women_family_set_child_visible(uuid, boolean);
drop function if exists public.women_family_reorder_children(uuid[]);
drop function if exists public.women_family_set_husband(uuid, text, boolean, boolean);
drop function if exists public.women_family_add_child(text, boolean, date, boolean);
drop function if exists private.women_family_set_husband_direct(uuid, text, boolean, boolean);
drop function if exists private.women_family_add_child_direct(text, boolean, date, boolean);

create or replace function private.self_relative_request(p_rpc text, p_args jsonb, p_kind text, p_name text)
returns void
language plpgsql security definer set search_path to 'public'
as $function$
declare
  me      uuid := public.current_profile_id();
  payload jsonb;
  k_label text := case p_kind when 'wife' then 'زوجة' when 'mother' then 'أم' when 'sister' then 'أخت' else 'قريبة' end;
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
end $function$;


alter table public.women_members
  drop column if exists spouse_shown,
  drop column if exists children_shown,
  drop column if exists hidden_children;
commit;
