-- مسار الموافقات: المالك يراجع طلبه هو (طلب المالك ٢٠٢٦-١٠-١٥ «لمن أعطي ملاحظة يقولي عند مسؤول آخر وأنا المالك»)
--
-- قبلها: خطوة المختص (توصية/طلب معلومات) على طلبك أنت تُرفض للجميع (own_request) — ولا مراقب نشط،
-- فالمالك (بديل المختص) ما يقدر يمرّر طلبه. الآن المالك مستثنى مثل الاعتماد (advance_admin_request: approve)
-- وتجاوز المدير؛ المدير والمراقب والمشرف ما زالوا لا يراجعون طلباتهم.
-- التغيير الوحيد: سطر is_own في فرع المختص. التراجع: supabase/rollback/20261015130000_approvals_owner_own_request_rollback.sql
-- التجربة: supabase/tests/family_links/approvals_workflow.test.mjs

create or replace function public.advance_admin_request(p_request_id uuid, p_action text, p_note text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  uid      uuid := auth.uid();
  me       uuid := public.current_profile_id();
  my_role  text := coalesce(public.current_user_role(), 'pending');
  act      text := lower(btrim(coalesce(p_action, '')));
  note     text := nullif(regexp_replace(coalesce(p_note, ''), '^\s+|\s+$', '', 'g'), '');
  r        public.admin_requests%rowtype;
  cur      text;
  nxt      text;
  is_own   boolean;
  label    text;
  m_name   text;
  about    text := '';
begin
  if act not in ('recommend_approve', 'recommend_reject', 'request_info', 'provide_info', 'approve', 'return') then
    raise exception 'إجراء غير معروف في مسار الموافقات' using errcode = '22023', hint = 'bad_action';
  end if;
  if uid is null or me is null then
    raise exception 'سجّل الدخول أولاً' using errcode = '42501', hint = 'not_allowed';
  end if;
  if not public.approvals_workflow_on() then
    raise exception 'مسار الموافقات متوقف — يُعالج الطلب بالطريقة المعتادة' using errcode = 'P0001', hint = 'workflow_off';
  end if;

  select * into r from public.admin_requests where id = p_request_id for update;
  if not found then
    raise exception 'الطلب غير موجود' using errcode = 'P0002', hint = 'request_not_found';
  end if;
  if r.status is distinct from 'pending' then
    raise exception 'تمت معالجة هذا الطلب مسبقاً' using errcode = 'P0001', hint = 'already_handled';
  end if;
  if public.workflow_specialist_role(r.request_type) is null then
    raise exception 'هذا النوع من الطلبات خارج مسار الموافقات' using errcode = 'P0001', hint = 'wrong_stage';
  end if;

  cur    := coalesce(r.stage, 'review');   -- معلّق بلا مرحلة (قبل تشغيل المفتاح) = عند المختص
  is_own := coalesce(r.requester_id = any (array[uid, me]), false) or coalesce(r.member_id = any (array[uid, me]), false);

  -- الصلاحية
  if act = 'provide_info' then
    if not coalesce(r.requester_id = any (array[uid, me]), false) then
      raise exception 'الرد على طلب المعلومات لصاحب الطلب فقط' using errcode = '42501', hint = 'not_allowed';
    end if;
  elsif act in ('approve', 'return') then
    if my_role not in ('owner', 'admin') then
      raise exception 'اعتماد الطلبات للمالك والمدير فقط' using errcode = '42501', hint = 'not_allowed';
    end if;
    if is_own and my_role <> 'owner' then
      raise exception 'لا يمكنك اعتماد طلبك — يعتمده مسؤول آخر' using errcode = '42501', hint = 'own_request';
    end if;
  else
    if not public.is_workflow_specialist(r.request_type) then
      raise exception 'مراجعة هذا الطلب للمختص' using errcode = '42501', hint = 'not_allowed';
    end if;
    if is_own and my_role <> 'owner' then
      raise exception 'لا يمكنك مراجعة طلبك — يراجعه مختص آخر' using errcode = '42501', hint = 'own_request';
    end if;
  end if;

  -- المرحلة
  if (act in ('recommend_approve', 'recommend_reject', 'request_info') and cur <> 'review')
     or (act = 'provide_info' and cur <> 'info')
     or (act in ('approve', 'return') and cur <> 'approve') then
    raise exception 'الطلب ليس في المرحلة المناسبة لهذا الإجراء' using errcode = 'P0001', hint = 'wrong_stage';
  end if;

  -- الملاحظة
  if note is null and act in ('recommend_reject', 'request_info', 'provide_info', 'return') then
    raise exception '%', case act
        when 'recommend_reject' then 'اكتب سبب التوصية بالرفض'
        when 'request_info'     then 'اكتب المعلومات المطلوبة من صاحب الطلب'
        when 'provide_info'     then 'اكتب ردّك'
        else 'اكتب سبب الإرجاع للمختص' end
      using errcode = '22023', hint = 'note_required';
  end if;

  -- التحديث (الحارس trg_zz_admin_request_workflow يسمح بأعمدة المسار داخل هذه الدالة فقط)
  perform set_config('approvals.advance', 'on', true);
  if act in ('recommend_approve', 'recommend_reject') then
    nxt := 'approve';
    update public.admin_requests
       set stage = nxt, stage_since = now(),
           recommendation = case when act = 'recommend_approve' then 'approve' else 'reject' end,
           recommendation_note = note, recommended_by = me, recommended_at = now()
     where id = r.id;
  elsif act = 'request_info' then
    nxt := 'info';
    update public.admin_requests set stage = nxt, stage_since = now(), info_request = note where id = r.id;
  elsif act = 'provide_info' then
    nxt := 'review';   -- السؤال يبقى في info_request للتاريخ، والرد في ملاحظة الخطوة
    update public.admin_requests set stage = nxt, stage_since = now() where id = r.id;
  elsif act = 'approve' then
    nxt := 'execute';
    update public.admin_requests
       set stage = nxt, stage_since = now(), approved_by = me, approved_at = now(), approval_note = note
     where id = r.id;
  else
    nxt := 'review';
    update public.admin_requests set stage = nxt, stage_since = now(), approval_note = note where id = r.id;
  end if;
  perform set_config('approvals.advance', '', true);

  insert into public.admin_request_steps (request_id, actor_id, actor_role, action, note)
  values (r.id, me, my_role, act, note);

  -- الإشعارات
  label  := public.admin_request_label(r.request_type);
  m_name := coalesce((select nullif(btrim(p.full_name), '') from public.profiles p where p.id = r.member_id), '');
  if m_name <> '' then
    about := ' لـ «' || m_name || '»';
  end if;

  if act in ('recommend_approve', 'recommend_reject') then
    perform public.approvals_notify(
      array(select p.id from public.profiles p where p.role in ('owner', 'admin') and p.status = 'active'),
      'توصية بانتظار اعتمادك',
      case when act = 'recommend_approve' then 'أوصى المختص بقبول ' || label || about
           else 'أوصى المختص برفض ' || label || about || E'\nالسبب: ' || note end,
      me, r.id, r.request_type, nxt, act);
  elsif act = 'request_info' then
    perform public.approvals_notify(array[r.requester_id], 'الإدارة تحتاج معلومات إضافية',
      'بخصوص ' || label || ': ' || note, me, r.id, r.request_type, nxt, act);
  elsif act = 'provide_info' then
    perform public.approvals_notify(array(select public.workflow_specialist_ids(r.request_type)),
      'وصل ردّ صاحب الطلب', label || about || ': ' || note, me, r.id, r.request_type, nxt, act);
  elsif act = 'approve' then
    perform public.approvals_notify(array(select public.workflow_specialist_ids(r.request_type)),
      'اعتمد المدير الطلب — جاهز للتنفيذ', label || about || ' معتمد، نفّذه الآن', me, r.id, r.request_type, nxt, act);
    perform public.approvals_notify(array[r.requester_id], 'تمت الموافقة على طلبك',
      'تمت الموافقة على ' || label || ' — يتم التنفيذ', me, r.id, r.request_type, nxt, act);
  else
    perform public.approvals_notify(array(select public.workflow_specialist_ids(r.request_type)),
      'أعاد المدير الطلب للمراجعة', label || about || E'\nالملاحظة: ' || note, me, r.id, r.request_type, nxt, act);
  end if;

  return jsonb_build_object('request_id', r.id, 'stage', nxt);
end;
$function$;

revoke all on function public.advance_admin_request(uuid, text, text) from public, anon;
grant execute on function public.advance_admin_request(uuid, text, text) to authenticated;
