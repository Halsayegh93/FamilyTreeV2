-- إضافة القريبات (الزوجة/الأم/الأخت) بموافقة الإدارة (قرار المالك ٢٠٢٦-١٠-٢٩ «نعم اصلح»، مثل الابن self_child_daily_limit=0).
-- • add_self_wife / add_self_mother / add_or_link_self_relative بنفس التوقيع ونوع الرجوع (uuid):
--   – الإدارة (is_team) أو المفتاح self_relative_requires_approval=false → الإضافة المباشرة كما كانت (ترجع معرّف المرأة).
--   – غيرهم: نفس الفحوص تجري «تجربة» وتُلغى (نفس رسائل الخطأ وhint)، ثم يُنشأ طلب admin_requests من نوع relative_add
--     وترجع NULL = «أُرسل للإدارة». طلب مطابق معلّق لنفس العضو لا يتكرر (يرجع NULL أيضاً).
-- • الدوال الأصلية بنصّها كما هي انتقلت إلى private.*_direct (لا تُنادى من التطبيقات).
-- • decide_admin_request: relative_add يُنفَّذ هنا — القبول يشغّل الدالة الأصلية بهوية صاحب الطلب (نفس الفحوص وقت القبول)،
--   الرفض يغلقه، وصاحب الطلب يُشعَر (المالك/المدير كالعادة). باقي الأنواع → private.decide_admin_request_core (الدالة السابقة حرفياً).
-- • حارس الإدراج يقبل relative_add من هذه الدوال فقط (app.self_relative_rpc).

insert into public.app_config (key, value, default_value, kind, category, label_ar, help_ar, is_public, sort)
values ('self_relative_requires_approval', 'true'::jsonb, 'true'::jsonb, 'bool', 'tree',
        'إضافة الزوجة والأم والأخت بموافقة الإدارة',
        'مفعّل: ما يضيفه العضو من زوجة أو أم أو أخت يصل الإدارة طلباً «إضافة قريبة» ولا يظهر في الشجرة قبل الموافقة. مطفأ: يُضاف مباشرة.',
        false, 64)
on conflict (key) do nothing;

-- ── ١) الدوال الأصلية → private.*_direct ──
alter function public.add_self_wife(text, boolean) set schema private;
alter function private.add_self_wife(text, boolean) rename to add_self_wife_direct;
alter function public.add_self_mother(text) set schema private;
alter function private.add_self_mother(text) rename to add_self_mother_direct;
alter function public.add_or_link_self_relative(text, uuid, uuid, text) set schema private;
alter function private.add_or_link_self_relative(text, uuid, uuid, text) rename to add_or_link_self_relative_direct;
revoke all on function private.add_self_wife_direct(text, boolean) from public, anon, authenticated;
revoke all on function private.add_self_mother_direct(text) from public, anon, authenticated;
revoke all on function private.add_or_link_self_relative_direct(text, uuid, uuid, text) from public, anon, authenticated;

-- ── ٢) الطلب ──
create or replace function private.self_relative_needs_request()
returns boolean language sql stable security definer set search_path to 'public' as $$
  select not public.is_team(auth.uid())
     and coalesce(current_setting('app.self_relative_exec', true), '') <> 'on'
     and public.config_bool('self_relative_requires_approval', true);
$$;

create or replace function private.self_relative_request(p_rpc text, p_args jsonb, p_kind text, p_name text)
returns void language plpgsql security definer set search_path to 'public' as $$
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
end $$;
revoke all on function private.self_relative_needs_request() from public, anon, authenticated;
revoke all on function private.self_relative_request(text, jsonb, text, text) from public, anon, authenticated;

-- ── ٣) الدوال العامة بنفس التوقيع ──
create or replace function public.add_self_wife(p_name text, p_hidden boolean default false)
returns uuid language plpgsql security definer set search_path to 'public' as $$
begin
  if not private.self_relative_needs_request() then
    return private.add_self_wife_direct(p_name, p_hidden);
  end if;
  begin  -- نفس فحوص الإضافة، ثم تُلغى
    perform private.add_self_wife_direct(p_name, p_hidden);
    raise exception 'dry_run' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform private.self_relative_request('add_self_wife',
    jsonb_build_object('p_name', btrim(coalesce(p_name, '')), 'p_hidden', coalesce(p_hidden, false)), 'wife', p_name);
  return null;
end $$;

create or replace function public.add_self_mother(p_name text)
returns uuid language plpgsql security definer set search_path to 'public' as $$
begin
  if not private.self_relative_needs_request() then
    return private.add_self_mother_direct(p_name);
  end if;
  begin
    perform private.add_self_mother_direct(p_name);
    raise exception 'dry_run' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform private.self_relative_request('add_self_mother',
    jsonb_build_object('p_name', btrim(coalesce(p_name, ''))), 'mother', p_name);
  return null;
end $$;

create or replace function public.add_or_link_self_relative(p_kind text, p_father_id uuid,
                                                            p_woman_id uuid default null, p_name text default null)
returns uuid language plpgsql security definer set search_path to 'public' as $$
declare nm text;
begin
  if not private.self_relative_needs_request() then
    return private.add_or_link_self_relative_direct(p_kind, p_father_id, p_woman_id, p_name);
  end if;
  begin
    perform private.add_or_link_self_relative_direct(p_kind, p_father_id, p_woman_id, p_name);
    raise exception 'dry_run' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  nm := coalesce(nullif(btrim(coalesce(p_name, '')), ''),
                 (select w.full_name from public.women_members w where w.id = p_woman_id));
  perform private.self_relative_request('add_or_link_self_relative',
    jsonb_build_object('p_kind', lower(btrim(coalesce(p_kind, ''))), 'p_father_id', p_father_id,
                       'p_woman_id', p_woman_id, 'p_name', nullif(btrim(coalesce(p_name, '')), '')),
    lower(btrim(coalesce(p_kind, ''))), nm);
  return null;
end $$;

revoke all on function public.add_self_wife(text, boolean) from public, anon;
revoke all on function public.add_self_mother(text) from public, anon;
revoke all on function public.add_or_link_self_relative(text, uuid, uuid, text) from public, anon;
grant execute on function public.add_self_wife(text, boolean) to authenticated, service_role;
grant execute on function public.add_self_mother(text) to authenticated, service_role;
grant execute on function public.add_or_link_self_relative(text, uuid, uuid, text) to authenticated, service_role;

-- ── ٤) حارس الإدراج: relative_add من دوال السيرفر فقط (تعديل نصّي دقيق على النسخة الحية) ──
do $mig$
declare d text := pg_get_functiondef('public.guard_admin_request_insert()'::regprocedure); n text;
begin
  n := replace(d, $x$'phone_change','child_add','news_report','content_report','account_delete','privacy_request') then$x$,
                  $x$'phone_change','child_add','news_report','content_report','account_delete','privacy_request','relative_add') then$x$);
  n := replace(n, E'  if new.requester_id is null\n',
                  E'  -- «إضافة قريبة» تُنشئها add_self_wife/add_self_mother/add_or_link_self_relative فقط (20261029140000)\n'
               || E'  if new.request_type = ''relative_add'' and coalesce(current_setting(''app.self_relative_rpc'', true), '''') <> ''on'' then\n'
               || E'    raise exception ''admin_request_type_not_allowed'' using errcode = ''42501'';\n'
               || E'  end if;\n'
               || E'  if new.requester_id is null\n');
  if n = d or length(n) - length(d) < 300 then
    raise exception 'guard_admin_request_insert: نص الحي تغيّر — راجع الترحيل';
  end if;
  execute n;
end $mig$;

-- ── ٥) الاسم العربي للنوع (التذكير/التصعيد) ──
do $mig$
declare d text := pg_get_functiondef('public.admin_request_label(text)'::regprocedure); n text;
begin
  n := replace(d, $x$    when 'edit_request'     then 'طلب التعديل'$x$,
                  $x$    when 'edit_request'     then 'طلب التعديل'
    when 'relative_add'     then 'طلب إضافة قريبة'
    when 'account_delete'   then 'طلب حذف الحساب'$x$);
  if n = d then raise exception 'admin_request_label: نص الحي تغيّر'; end if;
  execute n;
end $mig$;

-- ── ٦) القرار ──
alter function public.decide_admin_request(uuid, text, text, jsonb) set schema private;
alter function private.decide_admin_request(uuid, text, text, jsonb) rename to decide_admin_request_core;
revoke all on function private.decide_admin_request_core(uuid, text, text, jsonb) from public, anon, authenticated;

create or replace function public.decide_admin_request(p_request_id uuid, p_decision text, p_reason text default null,
                                                       p_overrides jsonb default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
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
    -- تنفيذ الدالة الأصلية بهوية صاحب الطلب (نفس فحوصها الآن)، ثم ترجع هوية المسؤول
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
end $$;
revoke all on function public.decide_admin_request(uuid, text, text, jsonb) from public, anon;
grant execute on function public.decide_admin_request(uuid, text, text, jsonb) to authenticated, service_role;
