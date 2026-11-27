-- نسخة الحي ٢٠٢٦-١١-٢٧ (pg_get_functiondef، قراءة فقط) — أساس التجارب التي ترقّع هذه الدالة.
CREATE OR REPLACE FUNCTION public.decide_admin_request(p_request_id uuid, p_decision text, p_reason text DEFAULT NULL::text, p_overrides jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
     or (not is_remove and v_rpc not in ('add_self_wife', 'add_self_mother', 'add_or_link_self_relative',
                                     'women_family_set_husband', 'women_family_add_child'))
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
    elsif v_rpc = 'women_family_set_husband' then
      new_id := private.women_family_set_husband_direct((a ->> 'p_family_id')::uuid, a ->> 'p_name',
                                                        coalesce((a ->> 'p_deceased')::boolean, false),
                                                        coalesce((a ->> 'p_visible')::boolean, false));
    elsif v_rpc = 'women_family_add_child' then
      new_id := private.women_family_add_child_direct(a ->> 'p_first_name', coalesce((a ->> 'p_female')::boolean, false),
                                                      (a ->> 'p_birth')::date, coalesce((a ->> 'p_deceased')::boolean, false));
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
$function$
;
