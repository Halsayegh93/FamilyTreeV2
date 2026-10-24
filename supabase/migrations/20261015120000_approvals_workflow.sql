-- مسار الموافقات (طلب المالك ٢٠٢٦-١٠-١٥ «مسار الموافقات» + «في قرارات يحتاج تجاوز»)
--
-- طلبات المراجعة (admin_requests) تمرّ بمسار مؤسسي خلف مفتاح يتحكم به المالك:
--   العضو يرسل ← المختص يراجع ويوصي (أو يطلب معلومات من صاحب الطلب) ← المدير (المالك/المدير)
--   يعتمد أو يرفض أو يعيد للمختص ← بعد الاعتماد يرجع للمختص فينفّذه بمسار الموافقة القديم نفسه
--   (decide_admin_request أو موافقة الانضمام/الربط في التطبيق) ← مغلق ويُشعَر العضو.
--   الرفض النهائي للمدير في أي مرحلة (مسار الرفض القديم، والسبب للعضو).
--   تجاوز المدير: في مرحلة «اعتماد» يقدر المالك/المدير ينفّذ مباشرة بالمسار القديم (تُسجَّل
--   خطوتان: اعتماد «اعتماد وتنفيذ مباشر من المدير» ثم تنفيذ). قبلها (مراجعة/معلومات) ممنوع.
--
-- المختص: المشرف للبلاغات (news_report, content_report)، المراقب لكل نوع آخر، ورسائل التواصل
-- (contact_message) خارج المسار. لا مراقب نشط اليوم → المالك والمدير يقومون مقام المختص حتى
-- يُعيَّن (is_workflow_specialist) فلا يعلق طلب.
--
-- المفتاح app_settings.approvals_workflow (افتراضياً مطفأ):
--   • مطفأ = لا فحص إطلاقاً، كل شيء كما اليوم. إطفاؤه وسط الطريق لا يكسر طلباً معلّقاً.
--   • شغّال = حارس قبل التحديث يمنع «تنفيذ» قبل اعتماد المدير حتى من النسخ القديمة التي تكتب
--     الحالة مباشرة (أندرويد/الموقع/الآيفون القديم) برسالة عربية (hint = approval_needs_manager).
-- أعمدة المسار لا تتغير إلا داخل advance_admin_request (علم محلي للمعاملة approvals.advance)
-- أو عند الإغلاق. الصيانة (مفتاح الخدمة، SQL، بلا مستخدم) تمر كما في الحراس الأخرى.
-- الإشعارات بنفس جدول/أعمدة/نوع decide_admin_request (kind = 'admin') فيوصلها trg_push_on_notification؛
-- تفاصيل المسار في details (type = approval_workflow) بلا request_id حتى لا تظهر أزرار «قبول سريع»
-- في نسخ الآيفون الحالية (isActionableRequest) فتغلق الطلب بلا تنفيذ.
--
-- التراجع: supabase/rollback/20261015120000_approvals_workflow_rollback.sql
-- التجربة: supabase/tests/family_links/approvals_workflow.test.mjs

-- ═══ ١) المفتاح ═══
alter table public.app_settings
  add column if not exists approvals_workflow boolean not null default false;
comment on column public.app_settings.approvals_workflow is
  'مسار الموافقات (طلب المالك ٢٠٢٦-١٠-١٥): مختص يوصي ← المدير يعتمد ← المختص ينفّذ. مطفأ = المسار القديم';

-- ═══ ٢) أعمدة المرحلة في الطلب ═══
alter table public.admin_requests
  add column if not exists stage               text,
  add column if not exists stage_since         timestamptz,
  add column if not exists recommendation      text,
  add column if not exists recommendation_note text,
  add column if not exists recommended_by      uuid,
  add column if not exists recommended_at      timestamptz,
  add column if not exists info_request        text,
  add column if not exists approved_by         uuid,
  add column if not exists approved_at         timestamptz,
  add column if not exists approval_note       text;
alter table public.admin_requests
  add constraint admin_requests_stage_check check (stage in ('review', 'info', 'approve', 'execute')),
  add constraint admin_requests_recommendation_check check (recommendation in ('approve', 'reject'));

-- ═══ ٣) سجل خطوات الطلب ═══
create table if not exists public.admin_request_steps (
  id          uuid primary key default gen_random_uuid(),
  request_id  uuid not null references public.admin_requests(id) on delete cascade,
  actor_id    uuid,
  actor_role  text,
  action      text not null,
  note        text,
  created_at  timestamptz not null default now(),
  constraint admin_request_steps_action_check check (action in ('submitted', 'recommend_approve', 'recommend_reject',
    'request_info', 'provide_info', 'approve', 'return', 'executed', 'rejected'))
);
create index if not exists admin_request_steps_request_idx on public.admin_request_steps (request_id, created_at);
comment on table public.admin_request_steps is
  'خطوات مسار الموافقات لكل طلب (طلب المالك ٢٠٢٦-١٠-١٥) — يكتبها السيرفر فقط';

alter table public.admin_request_steps enable row level security;
-- القراءة: الإدارة الأربعة، وصاحب الطلب/المعني به. لا كتابة مباشرة لأي مستخدم (دوال السيرفر فقط).
create policy admin_request_steps_select on public.admin_request_steps
  for select to authenticated
  using (
    public.current_user_role() = any (array['owner', 'admin', 'monitor', 'supervisor'])
    or exists (select 1 from public.admin_requests r
               where r.id = admin_request_steps.request_id
                 and (r.requester_id = any (array[auth.uid(), public.current_profile_id()])
                      or r.member_id = any (array[auth.uid(), public.current_profile_id()]))));
revoke all on public.admin_request_steps from public, anon;
revoke insert, update, delete, truncate, references, trigger on public.admin_request_steps from authenticated;
grant select on public.admin_request_steps to authenticated;
grant all on public.admin_request_steps to service_role;

-- ═══ ٤) دوال المسار ═══

-- هل المفتاح شغّال (يقرأ الإعداد بلا اعتبار لسياسات الجدول)
create or replace function public.approvals_workflow_on()
 returns boolean
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select coalesce((select bool_or(s.approvals_workflow) from public.app_settings s), false);
$function$;

-- مختص النوع: المشرف للبلاغات، رسائل التواصل خارج المسار (NULL)، والمراقب لكل نوع آخر
create or replace function public.workflow_specialist_role(p_type text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case
    when p_type in ('news_report', 'content_report') then 'supervisor'
    when p_type = 'contact_message' then null
    else 'monitor'
  end;
$function$;

-- المتصل مختص هذا النوع؟ أو مالك/مدير ولا يوجد مختص نشط بهذا الدور (حتى لا يعلق طلب)
create or replace function public.is_workflow_specialist(p_type text)
 returns boolean
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select case
    when public.workflow_specialist_role(p_type) is null then false
    when public.current_user_role() = public.workflow_specialist_role(p_type) then true
    when public.current_user_role() in ('owner', 'admin')
         and not exists (select 1 from public.profiles p
                         where p.role = public.workflow_specialist_role(p_type) and p.status = 'active') then true
    else false
  end;
$function$;

-- مستلمو إشعار «المختص»: أصحاب الدور النشطون، وإن لم يوجد أحد فالمالك والمدير النشطون
create or replace function public.workflow_specialist_ids(p_type text)
 returns setof uuid
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  with sp as (
    select p.id from public.profiles p
    where p.role = public.workflow_specialist_role(p_type) and p.status = 'active'
  )
  select id from sp
  union all
  select p.id from public.profiles p
  where p.role in ('owner', 'admin') and p.status = 'active' and not exists (select 1 from sp);
$function$;

-- اسم نوع الطلب للإشعارات
create or replace function public.admin_request_label(p_type text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case p_type
    when 'tree_edit'        then 'طلب تعديل الشجرة'
    when 'deceased_report'  then 'بلاغ الوفاة'
    when 'child_add'        then 'طلب إضافة ابن'
    when 'name_change'      then 'طلب تغيير الاسم'
    when 'family_change'    then 'طلب تغيير العائلة'
    when 'phone_change'     then 'طلب تغيير الرقم'
    when 'photo_suggestion' then 'اقتراح الصورة'
    when 'news_report'      then 'البلاغ عن خبر'
    when 'content_report'   then 'البلاغ عن محتوى'
    when 'join_request'     then 'طلب الانضمام'
    when 'link_request'     then 'طلب الانضمام'
    when 'edit_request'     then 'طلب التعديل'
    else 'الطلب'
  end;
$function$;

-- إشعار موجّه (نفس أعمدة decide_admin_request: target/title/body/kind 'admin'/created_by)
-- لا يُشعَر المتصل نفسه. تفاصيل المسار في details لتطبيق الآيفون الجديد.
create or replace function public.approvals_notify(p_targets uuid[], p_title text, p_body text, p_actor uuid,
                                                   p_request_id uuid, p_request_type text, p_stage text, p_action text)
 returns integer
 language plpgsql
 set search_path to 'public'
as $function$
declare
  n integer;
begin
  insert into public.notifications (target_member_id, title, body, kind, created_by, details)
  select s.t, p_title, p_body, 'admin',
         case when exists (select 1 from public.profiles a where a.id = p_actor) then p_actor end,
         jsonb_build_object('type', 'approval_workflow', 'request_id', p_request_id,
                            'request_type', p_request_type, 'stage', p_stage, 'action', p_action)
  from (select distinct x as t from unnest(p_targets) x) s
  where s.t is not null and s.t is distinct from p_actor
    and exists (select 1 from public.profiles p where p.id = s.t);
  get diagnostics n = row_count;
  return n;
end;
$function$;

-- ═══ ٥) خطوة في المسار ═══
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
    if is_own then
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

-- ═══ ٦) المرحلة عند الإدراج (بعد trg_guard_admin_request_insert — الترتيب أبجدي) ═══
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

create or replace function public.log_admin_request_submitted()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  if new.stage is not null and new.status is not distinct from 'pending' then
    insert into public.admin_request_steps (request_id, actor_id, actor_role, action)
    values (new.id, new.requester_id,
            (select case when p.status = 'active' then p.role when p.status in ('frozen', 'deleted') then p.status
                         else 'pending' end
             from public.profiles p where p.id = new.requester_id),
            'submitted');
  end if;
  return new;
end;
$function$;

-- ═══ ٧) حارس التحديث ═══
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

drop trigger if exists trg_zz_admin_request_stage on public.admin_requests;
create trigger trg_zz_admin_request_stage
  before insert on public.admin_requests
  for each row execute function public.set_admin_request_stage();

drop trigger if exists trg_zz_admin_request_submitted on public.admin_requests;
create trigger trg_zz_admin_request_submitted
  after insert on public.admin_requests
  for each row execute function public.log_admin_request_submitted();

drop trigger if exists trg_zz_admin_request_workflow on public.admin_requests;
create trigger trg_zz_admin_request_workflow
  before update on public.admin_requests
  for each row execute function public.guard_admin_request_workflow();

-- ═══ ٨) الصلاحيات ═══
revoke all on function public.advance_admin_request(uuid, text, text) from public, anon;
grant execute on function public.advance_admin_request(uuid, text, text) to authenticated;
revoke all on function public.approvals_workflow_on() from public, anon;
grant execute on function public.approvals_workflow_on() to authenticated;
revoke all on function public.workflow_specialist_role(text) from public, anon;
grant execute on function public.workflow_specialist_role(text) to authenticated;
revoke all on function public.is_workflow_specialist(text) from public, anon;
grant execute on function public.is_workflow_specialist(text) to authenticated;
-- داخلية فقط
revoke all on function public.workflow_specialist_ids(text) from public, anon, authenticated;
revoke all on function public.admin_request_label(text) from public, anon, authenticated;
revoke all on function public.approvals_notify(uuid[], text, text, uuid, uuid, text, text, text) from public, anon, authenticated;
revoke all on function public.set_admin_request_stage() from public, anon, authenticated;
revoke all on function public.log_admin_request_submitted() from public, anon, authenticated;
revoke all on function public.guard_admin_request_workflow() from public, anon, authenticated;
