-- مسار الموافقات: «طلب معلومات» منظّم (طلب المالك ٢٠٢٦-١٠-١٥ «اذا رد الطلب و ناقص رقم هاتف او تاريخ
-- ميلاد يظهر امر التاريخ او الهاتف عند العضو للرد و الادارة تختار الناقص»)
--
-- المختص يختار الناقص (رقم الهاتف، تاريخ الميلاد، تاريخ الوفاة، الاسم الكامل) بدل سؤال حرّ فقط:
--   • admin_requests.info_fields text[] = الحقول المطلوبة ('phone','birth_date','death_date','full_name','text')
--   • admin_requests.info_reply  jsonb  = ردّ العضو المنظّم بعد الفحص (المطلوب فقط + 'text')
--   كلاهما من أعمدة المسار: لا يكتبهما إلا advance_admin_request (الحارس + مسح الإدراج)، ويبقيان بعد الإغلاق للتاريخ.
-- advance_admin_request صارت (p_request_id, p_action, p_note, p_fields, p_values) — الدالة القديمة بثلاث معاملات
-- تُحذف أولاً فيبقى مرشّح واحد لـ PostgREST، والنسخ الحالية تستدعيها بالأسماء الثلاثة فتعمل كما هي.
--   • request_info: الملاحظة مطلوبة إلا إذا اختير حقل واحد على الأقل (غير 'text')؛ المجهول → bad_action.
--     إشعار صاحب الطلب يسمّي المطلوب بالعربي + الملاحظة.
--   • provide_info: طُلبت حقول → قيمة صالحة لكل حقل (الهاتف ٨–١٥ رقماً، التاريخ yyyy-mm-dd وليس في المستقبل،
--     الاسم الكامل كلمتان على الأقل) وإلا note_required برسالة تسمّي الناقص؛ ملاحظة الخطوة ملخّص مقروء يكتبه
--     السيرفر («رقم الهاتف: …»، الرقم والتاريخ معزولان اتجاهياً). لم تُطلب حقول → كما كان (الملاحظة مطلوبة).
-- كل ما عدا ذلك كما في 20261015120000 + 20261015130000 حرفياً (استثناء المالك من مراجعة طلبه).
--
-- التراجع: supabase/rollback/20261015150000_approvals_info_fields_rollback.sql (يعيد حالة 20261015130000 حرفياً)
-- التجربة: supabase/tests/family_links/approvals_workflow.test.mjs

-- ═══ ١) الأعمدة ═══
alter table public.admin_requests
  add column if not exists info_fields text[],
  add column if not exists info_reply  jsonb;
alter table public.admin_requests
  add constraint admin_requests_info_fields_check
    check (info_fields <@ array['phone', 'birth_date', 'death_date', 'full_name', 'text']::text[]),
  add constraint admin_requests_info_reply_check
    check (info_reply is null or jsonb_typeof(info_reply) = 'object');
comment on column public.admin_requests.info_fields is
  'مسار الموافقات: الحقول التي طلبها المختص من صاحب الطلب (phone, birth_date, death_date, full_name, text)';
comment on column public.admin_requests.info_reply is
  'مسار الموافقات: ردّ صاحب الطلب المنظّم بعد فحص السيرفر ({"phone": "+965…", "birth_date": "yyyy-mm-dd", …, "text": "…"})';

-- ═══ ٢) اسم الحقل بالعربي (للإشعار وملخّص الخطوة) ═══
create or replace function public.approvals_info_field_label(p_field text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case p_field
    when 'phone'      then 'رقم الهاتف'
    when 'birth_date' then 'تاريخ الميلاد'
    when 'death_date' then 'تاريخ الوفاة'
    when 'full_name'  then 'الاسم الكامل'
    when 'text'       then 'توضيح مكتوب'
    else p_field
  end;
$function$;

-- ═══ ٣) خطوة في المسار (بالحقول) ═══
drop function if exists public.advance_admin_request(uuid, text, text);

create or replace function public.advance_admin_request(p_request_id uuid, p_action text, p_note text default null,
                                                        p_fields text[] default null, p_values jsonb default null)
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
  allowed  constant text[] := array['phone', 'birth_date', 'death_date', 'full_name', 'text'];
  digits_a constant text := '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹';
  digits_e constant text := '01234567890123456789';
  today    date := (now() at time zone 'Asia/Kuwait')::date;
  fields   text[];        -- request_info: الحقول المطلوبة بعد التنظيف (بلا تكرار)
  vals     jsonb;         -- provide_info: ما أرسله التطبيق
  reply    jsonb;         -- provide_info: الرد بعد الفحص (المطلوب فقط + text)
  items    text;          -- «رقم الهاتف، تاريخ الميلاد»
  step     text;          -- ملاحظة الخطوة في السجل
  f        text;
  v        text;
  d        date;
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

  -- الحقول المطلوبة: من القائمة المعروفة فقط، بلا تكرار (الفراغ يُتجاهل)
  if act = 'request_info' and p_fields is not null then
    foreach f in array p_fields loop
      f := lower(btrim(coalesce(f, '')));
      continue when f = '';
      if not (f = any (allowed)) then
        raise exception 'حقل غير معروف في طلب المعلومات: %', f using errcode = '22023', hint = 'bad_action';
      end if;
      if fields is null or not (f = any (fields)) then
        fields := array_append(fields, f);
      end if;
    end loop;
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

  -- الملاحظة: طلب معلومات بحقل محدّد (غير «توضيح مكتوب») لا يحتاجها، والرد على حقول يُفحص حقلاً حقلاً تحت
  if note is null and (act in ('recommend_reject', 'return')
                       or (act = 'request_info' and (fields is null or fields <@ array['text']))
                       or (act = 'provide_info' and coalesce(cardinality(r.info_fields), 0) = 0)) then
    raise exception '%', case act
        when 'recommend_reject' then 'اكتب سبب التوصية بالرفض'
        when 'request_info'     then 'اكتب المعلومات المطلوبة من صاحب الطلب'
        when 'provide_info'     then 'اكتب ردّك'
        else 'اكتب سبب الإرجاع للمختص' end
      using errcode = '22023', hint = 'note_required';
  end if;

  step := note;
  if act = 'request_info' and fields is not null then
    items := array_to_string(array(select public.approvals_info_field_label(x) from unnest(fields) x), '، ');
    step  := 'المطلوب: ' || items || coalesce(E'\n' || note, '');
  end if;

  -- ردّ العضو على حقول محدّدة: قيمة صالحة لكل حقل، والملخّص المقروء من السيرفر لا من التطبيق
  if act = 'provide_info' and coalesce(cardinality(r.info_fields), 0) > 0 then
    vals  := case when jsonb_typeof(p_values) = 'object' then p_values else '{}'::jsonb end;
    reply := '{}'::jsonb;
    step  := null;
    foreach f in array r.info_fields loop
      continue when f = 'text';
      label := public.approvals_info_field_label(f);
      v := btrim(coalesce(vals ->> f, ''));
      if v = '' then
        raise exception 'أدخل %', label using errcode = '22023', hint = 'note_required';
      end if;
      if f = 'phone' then
        v := regexp_replace(translate(v, digits_a, digits_e), '[\s\-\(\)]', '', 'g');
        if v !~ '^\+?[0-9]{8,15}$' then
          raise exception 'رقم الهاتف غير صحيح — من ٨ إلى ١٥ رقماً' using errcode = '22023', hint = 'note_required';
        end if;
      elsif f in ('birth_date', 'death_date') then
        v := translate(v, digits_a, digits_e);
        if v !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
          raise exception '% غير صحيح — بصيغة سنة-شهر-يوم', label using errcode = '22023', hint = 'note_required';
        end if;
        begin
          d := v::date;
        exception when others then
          raise exception '% غير صحيح', label using errcode = '22023', hint = 'note_required';
        end;
        if d > today then
          raise exception '% لا يكون في المستقبل', label using errcode = '22023', hint = 'note_required';
        end if;
      else
        v := left(regexp_replace(v, '\s+', ' ', 'g'), 200);
        if cardinality(string_to_array(v, ' ')) < 2 then
          raise exception 'اكتب الاسم الكامل (الاسم واسم الأب على الأقل)' using errcode = '22023', hint = 'note_required';
        end if;
      end if;
      reply := reply || jsonb_build_object(f, v);
      -- الرقم والتاريخ معزولان باتجاه اليسار لليمين (U+2066 … U+2069) فلا ينقلبان داخل السطر العربي
      step  := coalesce(step || E'\n', '') || label || ': '
               || case when f = 'full_name' then v else chr(8294) || v || chr(8297) end;
    end loop;
    v := left(nullif(btrim(coalesce(vals ->> 'text', '')), ''), 500);
    if v is null and 'text' = any (r.info_fields) then
      raise exception 'اكتب التوضيح المطلوب' using errcode = '22023', hint = 'note_required';
    end if;
    if v is not null then
      reply := reply || jsonb_build_object('text', v);
      step  := coalesce(step || E'\n', '') || v;
    end if;
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
    -- سؤال جديد: الرد السابق يبقى في سجل الخطوات فقط
    update public.admin_requests
       set stage = nxt, stage_since = now(), info_request = note, info_fields = fields, info_reply = null
     where id = r.id;
  elsif act = 'provide_info' then
    nxt := 'review';   -- السؤال والحقول تبقى للتاريخ، والرد في info_reply وملاحظة الخطوة
    update public.admin_requests set stage = nxt, stage_since = now(), info_reply = reply where id = r.id;
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
  values (r.id, me, my_role, act, step);

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
      case when items is null then 'بخصوص ' || label || ': ' || note
           else 'بخصوص ' || label || ' — المطلوب: ' || items || coalesce(E'\n' || note, '') end,
      me, r.id, r.request_type, nxt, act);
  elsif act = 'provide_info' then
    perform public.approvals_notify(array(select public.workflow_specialist_ids(r.request_type)),
      'وصل ردّ صاحب الطلب',
      case when reply is null then label || about || ': ' || note else label || about || E':\n' || step end,
      me, r.id, r.request_type, nxt, act);
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

-- ═══ ٤) المرحلة عند الإدراج: الحقلان من أعمدة المسار (يُمسحان من المستخدم) ═══
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
    new.info_fields := null; new.info_reply := null;
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

-- ═══ ٥) حارس التحديث: الحقلان محميّان مثل بقية أعمدة المسار، ولا يُمسحان عند الإغلاق ═══
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
              new.recommended_at, new.info_request, new.approved_by, new.approved_at, new.approval_note,
              new.info_fields, new.info_reply)
             is distinct from
             (old.stage, old.stage_since, old.recommendation, old.recommendation_note, old.recommended_by,
              old.recommended_at, old.info_request, old.approved_by, old.approved_at, old.approval_note,
              old.info_fields, old.info_reply);
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
  new.info_fields := old.info_fields; new.info_reply := old.info_reply;

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

-- ═══ ٦) الصلاحيات ═══
revoke all on function public.advance_admin_request(uuid, text, text, text[], jsonb) from public, anon;
grant execute on function public.advance_admin_request(uuid, text, text, text[], jsonb) to authenticated;
-- داخلية فقط
revoke all on function public.approvals_info_field_label(text) from public, anon, authenticated;
