-- تراجع 20261015150000 («طلب معلومات» منظّم): يعيد حالة 20261015130000 حرفياً — advance_admin_request بثلاث
-- معاملات (استثناء المالك كما هو)، والحارس ومسح الإدراج كما في 20261015120000، ويحذف العمودين والقيدين ودالة الأسماء.
-- الحقول المطلوبة وردود الأعضاء المنظّمة تضيع (ملاحظات الخطوات في admin_request_steps تبقى مقروءة).
-- نسخة الآيفون التي ترسل p_fields/p_values تحتاج الدالة الجديدة — لا تُرجع قبل إرجاع التطبيق أو إخفاء الحقول فيه.

drop function if exists public.advance_admin_request(uuid, text, text, text[], jsonb);

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

create or replace function public.set_admin_request_stage()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  maint boolean := coalesce(auth.role() = 'service_role', false)
                   or (auth.role() is null and session_user in ('postgres', 'supabase_admin', 'supabase_auth_admin'));
begin
  -- أعمدة المسار يكتبها السيرفر وحده: ما يرسله المستخدم يُمسح (الصيانة تحتفظ بقيمها)
  if not maint then
    new.stage := null; new.stage_since := null;
    new.recommendation := null; new.recommendation_note := null; new.recommended_by := null; new.recommended_at := null;
    new.info_request := null; new.approved_by := null; new.approved_at := null; new.approval_note := null;
  end if;
  if new.stage is null and new.status is not distinct from 'pending'
     and public.workflow_specialist_role(new.request_type) is not null
     and public.approvals_workflow_on() then
    new.stage := 'review';
    new.stage_since := now();
  end if;
  return new;
end;
$function$;

create or replace function public.guard_admin_request_workflow()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  uid      uuid := auth.uid();
  me       uuid := public.current_profile_id();
  maint    boolean := coalesce(auth.role() = 'service_role', false)
                      or (auth.role() is null and session_user in ('postgres', 'supabase_admin', 'supabase_auth_admin'));
  via_fn   boolean := coalesce(current_setting('approvals.advance', true), '') = 'on';
  closing  boolean := old.status is not distinct from 'pending' and new.status is distinct from 'pending';
  changed  boolean;
  cur      text := coalesce(old.stage, 'review');
  my_role  text;
  is_own   boolean;
  direct   boolean := false;
  t0       timestamptz;
begin
  changed := (new.stage, new.stage_since, new.recommendation, new.recommendation_note, new.recommended_by,
              new.recommended_at, new.info_request, new.approved_by, new.approved_at, new.approval_note)
             is distinct from
             (old.stage, old.stage_since, old.recommendation, old.recommendation_note, old.recommended_by,
              old.recommended_at, old.info_request, old.approved_by, old.approved_at, old.approval_note);
  -- أي تعديل آخر (الرد، نقل المعرّفات عند الدمج، …) يمر كما هو
  if not closing and not changed then
    return new;
  end if;

  -- السيرفر وصيانة SQL والمهام، وبلا دخول (سياسات الجدول ترفضه): لا فحص — ترتيب الإغلاق فقط
  if maint or uid is null then
    if closing then
      if old.stage is not null then
        insert into public.admin_request_steps (request_id, actor_id, actor_role, action, note)
        values (old.id, me, null, case when new.status = 'approved' then 'executed' else 'rejected' end,
                nullif(btrim(coalesce(new.admin_reply, '')), ''));
      end if;
      new.stage := null; new.stage_since := null;
    end if;
    return new;
  end if;

  if not closing then
    if via_fn then
      return new;   -- advance_admin_request
    end if;
    raise exception 'مراحل الطلب تتغيّر من مسار الموافقات فقط' using errcode = '42501', hint = 'not_allowed';
  end if;

  -- إغلاق من مستخدم: أعمدة المسار من السيرفر لا من التطبيق
  new.recommendation := old.recommendation; new.recommendation_note := old.recommendation_note;
  new.recommended_by := old.recommended_by; new.recommended_at := old.recommended_at;
  new.info_request := old.info_request; new.approved_by := old.approved_by;
  new.approved_at := old.approved_at; new.approval_note := old.approval_note;

  -- المفتاح مطفأ أو النوع خارج المسار: لا فحص (المسار القديم) — ترتيب ما بدأ في المسار فقط
  if not public.approvals_workflow_on() or public.workflow_specialist_role(old.request_type) is null then
    if old.stage is not null then
      insert into public.admin_request_steps (request_id, actor_id, actor_role, action, note)
      values (old.id, me, public.current_user_role(),
              case when new.status = 'approved' then 'executed' else 'rejected' end,
              nullif(btrim(coalesce(new.admin_reply, '')), ''));
    end if;
    new.stage := null; new.stage_since := null;
    return new;
  end if;

  my_role := coalesce(public.current_user_role(), 'pending');
  is_own  := coalesce(old.requester_id = any (array[uid, me]), false) or coalesce(old.member_id = any (array[uid, me]), false);

  if new.status = 'approved' then
    if cur = 'execute' then
      -- بعد اعتماد المدير: التنفيذ للمختص
      if not public.is_workflow_specialist(old.request_type) then
        raise exception 'تنفيذ الطلب للمختص بعد اعتماد المدير' using errcode = '42501', hint = 'not_allowed';
      end if;
    elsif cur = 'approve' and my_role in ('owner', 'admin') then
      -- تجاوز المدير: اعتماد وتنفيذ مباشر (طلب المالك ٢٠٢٦-١٠-١٥ «في قرارات يحتاج تجاوز»)
      if is_own and my_role <> 'owner' then
        raise exception 'لا يمكنك اعتماد طلبك — يعتمده مسؤول آخر' using errcode = '42501', hint = 'own_request';
      end if;
      direct := true;
      new.approved_by := me;
      new.approved_at := now();
    else
      raise exception 'الطلب يحتاج اعتماد المدير قبل التنفيذ' using errcode = 'P0001', hint = 'approval_needs_manager';
    end if;
  else
    -- الرفض النهائي للمدير في أي مرحلة؛ المختص يوصي بالرفض فقط
    if my_role not in ('owner', 'admin') then
      raise exception 'رفض الطلب للمالك والمدير — المختص يوصي بالرفض' using errcode = '42501', hint = 'not_allowed';
    end if;
  end if;

  new.stage := null;
  new.stage_since := null;

  t0 := clock_timestamp();
  if direct then
    insert into public.admin_request_steps (request_id, actor_id, actor_role, action, note, created_at)
    values (old.id, me, my_role, 'approve', 'اعتماد وتنفيذ مباشر من المدير', t0);
  end if;
  insert into public.admin_request_steps (request_id, actor_id, actor_role, action, note, created_at)
  values (old.id, me, my_role, case when new.status = 'approved' then 'executed' else 'rejected' end,
          nullif(btrim(coalesce(new.admin_reply, '')), ''),
          case when direct then t0 + interval '1 millisecond' else t0 end);

  -- المالك/المدير يُشعِر صاحب الطلب من مسار الموافقة القديم (decide_admin_request / التطبيق)؛
  -- تنفيذ المختص (مراقب/مشرف) لا يُشعِره هناك، فيُشعَر من هنا. الانضمام/الربط يُشعِر به التطبيق
  -- عند التفعيل («تم قبول طلبك») فلا تكرار.
  if new.status = 'approved' and my_role not in ('owner', 'admin')
     and old.request_type not in ('join_request', 'link_request') then
    perform public.approvals_notify(array[old.requester_id], 'تم تنفيذ طلبك',
      'تم تنفيذ ' || public.admin_request_label(old.request_type) || ' بعد اعتماد الإدارة',
      me, old.id, old.request_type, null, 'executed');
  end if;
  return new;
end;
$function$;

drop function if exists public.approvals_info_field_label(text);

alter table public.admin_requests
  drop constraint if exists admin_requests_info_fields_check,
  drop constraint if exists admin_requests_info_reply_check,
  drop column if exists info_fields,
  drop column if exists info_reply;
