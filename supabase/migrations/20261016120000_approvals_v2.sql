-- مسار الموافقات ٢ (طلب المالك ٢٠٢٦-١٠-١٦ «مسار الموافقات ٢»)
--
-- فوق مسار الموافقات (20261015120000 + 20261015130000 + 20261015150000) وكلها خلف المفتاح نفسه
-- app_settings.approvals_workflow — مطفأ = المسار القديم حرفياً (لا أولوية ولا استلام ولا تذكير):
--   • الأولوية: admin_requests.priority ('normal' | 'urgent'). بلاغ الوفاة مستعجل تلقائياً، والمختص/المالك/المدير
--     يغيّرها (mark_urgent / mark_normal). المستعجل يُشعِر المختص والمالك والمدير فور وصوله.
--   • المسار السريع: الأنواع في app_settings.approvals_fast_types (افتراضياً إضافة ابن) تصل مباشرة لمرحلة
--     «اعتماد» (fast_track) بخطوتين «submitted» ثم «fast_track» ويُشعَر المالك والمدير.
--   • الاستلام: assigned_to/assigned_at — المختص يستلم الطلب (claim) في المراجعة/التنفيذ، والمالك/المدير في
--     الاعتماد؛ لا يتصرف غيره فيه (hint = claimed_by_other برسالة فيها اسمه الأول) إلا المالك (يأخذه منه).
--     الترك (release) للمستلم أو المالك أو المدير. التوصية تفكّ الاستلام، والاعتماد/الإرجاع يعيدانه لمن أوصى
--     إن بقي مختصاً، وطلب المعلومات وردّه يبقيانه.
--   • المهلة والتصعيد: approvals_sla_tick() كل ١٥ دقيقة (pg_cron 'approvals-sla') — تذكير بعد مهلة المرحلة
--     (approvals_sla_hours / approvals_urgent_sla_hours)، وتصعيد للمالك والمدير بعد approvals_escalate_hours
--     (approvals_urgent_escalate_hours): يُفكّ الاستلام ويقدر المالك/المدير يتصرف بدل المختص
--     (can_act_as_specialist). طلب معلومات بلا رد ٤٨ ساعة → تذكير صاحب الطلب. كل تغيير مرحلة يصفّر المؤقتين.
--   • قوالب الردود (approval_templates) والملاحظات الداخلية (admin_request_notes — للإدارة فقط، لا يراها
--     صاحب الطلب ولا الأعضاء) وتقرير الأداء approvals_report(من، إلى) للمالك والمدير والمراقب.
-- أعمدة المسار الجديدة محميّة مثل القديمة: لا يغيّرها إلا advance_admin_request أو مهمة السيرفر أو الصيانة،
-- وتُمسح عند إدراج المستخدم (إلا ما يضعه مشغّل الإدراج)، والإغلاق لا يمسّها (تبقى للتاريخ).
-- advance_admin_request بالتوقيع نفسه (٥ معاملات) وكل سلوكه السابق كما هو؛ ترجع الآن أيضاً assigned_to و priority.
--
-- التراجع: supabase/rollback/20261016120000_approvals_v2_rollback.sql (يعيد حالة 20261015170000 الحية حرفياً)
-- التجربة: supabase/tests/family_links/approvals_v2.test.mjs

-- ═══ ١) أعمدة الطلب ═══
alter table public.admin_requests
  add column if not exists priority     text not null default 'normal',
  add column if not exists assigned_to  uuid,
  add column if not exists assigned_at  timestamptz,
  add column if not exists reminded_at  timestamptz,
  add column if not exists escalated_at timestamptz,
  add column if not exists fast_track   boolean not null default false;
alter table public.admin_requests
  drop constraint if exists admin_requests_priority_check,
  add constraint admin_requests_priority_check check (priority in ('normal', 'urgent'));
comment on column public.admin_requests.priority is
  'مسار الموافقات ٢: الأولوية (normal | urgent) — بلاغ الوفاة مستعجل تلقائياً، ويغيّرها المختص/المالك/المدير';
comment on column public.admin_requests.assigned_to is
  'مسار الموافقات ٢: من استلم الطلب (لا يتصرف غيره فيه إلا المالك)';
comment on column public.admin_requests.assigned_at is 'مسار الموافقات ٢: وقت الاستلام';
comment on column public.admin_requests.reminded_at is 'مسار الموافقات ٢: وقت تذكير المرحلة الحالية (يُصفَّر مع كل مرحلة)';
comment on column public.admin_requests.escalated_at is
  'مسار الموافقات ٢: وقت تصعيد المرحلة الحالية للمالك والمدير (يُصفَّر مع كل مرحلة)';
comment on column public.admin_requests.fast_track is
  'مسار الموافقات ٢: وصل مباشرة لمرحلة الاعتماد (app_settings.approvals_fast_types)';

-- ═══ ٢) سجل الخطوات: الإجراءات الجديدة + صاحب العلاقة بالخطوة ═══
alter table public.admin_request_steps
  add column if not exists subject_id uuid;
comment on column public.admin_request_steps.subject_id is
  'مسار الموافقات ٢: المستلم السابق في خطوات الأخذ/الترك/التذكير/التصعيد (للتقرير)';
alter table public.admin_request_steps
  drop constraint if exists admin_request_steps_action_check,
  add constraint admin_request_steps_action_check check (action in ('submitted', 'recommend_approve', 'recommend_reject',
    'request_info', 'provide_info', 'approve', 'return', 'executed', 'rejected',
    'claim', 'release', 'priority', 'escalated', 'reminded', 'fast_track'));

-- ═══ ٣) الإعدادات (يعدّلها المالك بسياسة app_settings الحالية، ويقرؤها كل مسجّل) ═══
alter table public.app_settings
  add column if not exists approvals_fast_types            text[]  not null default array['child_add'],
  add column if not exists approvals_sla_hours             integer not null default 24,
  add column if not exists approvals_escalate_hours        integer not null default 48,
  add column if not exists approvals_urgent_sla_hours      integer not null default 6,
  add column if not exists approvals_urgent_escalate_hours integer not null default 12;
alter table public.app_settings
  drop constraint if exists app_settings_approvals_hours_check,
  add constraint app_settings_approvals_hours_check check (approvals_sla_hours > 0 and approvals_escalate_hours > 0
    and approvals_urgent_sla_hours > 0 and approvals_urgent_escalate_hours > 0);
comment on column public.app_settings.approvals_fast_types is
  'مسار الموافقات ٢: أنواع الطلبات التي تصل مباشرة للمدير (مسار سريع)';
comment on column public.app_settings.approvals_sla_hours is 'مسار الموافقات ٢: ساعات المرحلة قبل التذكير (عادي)';
comment on column public.app_settings.approvals_escalate_hours is
  'مسار الموافقات ٢: ساعات المراجعة/التنفيذ قبل التصعيد للمالك والمدير (عادي)';
comment on column public.app_settings.approvals_urgent_sla_hours is 'مسار الموافقات ٢: ساعات المرحلة قبل التذكير (مستعجل)';
comment on column public.app_settings.approvals_urgent_escalate_hours is
  'مسار الموافقات ٢: ساعات المراجعة/التنفيذ قبل التصعيد (مستعجل)';

-- ═══ ٤) دوال مساعدة ═══

-- المالك والمدير النشطون (مستلمو «الاعتماد» والتصعيد)
create or replace function public.approvals_manager_ids()
 returns setof uuid
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select p.id from public.profiles p where p.role in ('owner', 'admin') and p.status = 'active';
$function$;

-- يقدر المتصل يتصرف كمختص في هذا الطلب؟ مختص النوع (أو بديله)، أو مالك/مدير والطلب مصعَّد
create or replace function public.can_act_as_specialist(p_request public.admin_requests)
 returns boolean
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select public.workflow_specialist_role(p_request.request_type) is not null
     and (public.is_workflow_specialist(p_request.request_type)
          or (p_request.escalated_at is not null
              and coalesce(public.current_user_role(), '') in ('owner', 'admin')));
$function$;

-- نفسها بمعرّف الطلب (للتطبيقات: rpc can_act_as_specialist {p_request_id})
create or replace function public.can_act_as_specialist(p_request_id uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select coalesce((select public.can_act_as_specialist(r) from public.admin_requests r where r.id = p_request_id), false);
$function$;

-- هل هذا الشخص (لا المتصل) ما زال مختص النوع أو بديله؟ — لإعادة الاستلام لمن أوصى عند الاعتماد/الإرجاع
create or replace function public.approvals_member_can_specialize(p_member uuid, p_type text)
 returns boolean
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select public.workflow_specialist_role(p_type) is not null and exists (
    select 1 from public.profiles p
    where p.id = p_member and p.status = 'active'
      and (p.role = public.workflow_specialist_role(p_type)
           or (p.role in ('owner', 'admin')
               and not exists (select 1 from public.profiles s
                               where s.role = public.workflow_specialist_role(p_type) and s.status = 'active'))));
$function$;

-- الاسم الأول للرسائل («هذا الطلب يتابعه «علي»…»)
create or replace function public.approvals_first_name(p_member uuid)
 returns text
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select coalesce((select coalesce(nullif(btrim(p.first_name), ''), nullif(split_part(btrim(coalesce(p.full_name, '')), ' ', 1), ''))
                   from public.profiles p where p.id = p_member), 'مسؤول آخر');
$function$;

-- رفض «الطلب عند غيرك»
create or replace function public.approvals_raise_claimed(p_holder uuid)
 returns void
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
begin
  raise exception 'هذا الطلب يتابعه «%» — لا يتصرف فيه غيره حتى يتركه', public.approvals_first_name(p_holder)
    using errcode = '42501', hint = 'claimed_by_other';
end;
$function$;

-- ═══ ٥) خطوة في المسار (التوقيع نفسه + claim / release / mark_urgent / mark_normal) ═══
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
  is_mgr   boolean := my_role in ('owner', 'admin');
  holder   uuid;          -- المستلم بعد الخطوة
  prev     uuid;          -- المستلم قبلها (الأخذ/الترك)
  prio     text;          -- الأولوية بعد الخطوة
  targets  uuid[];
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
  if act not in ('recommend_approve', 'recommend_reject', 'request_info', 'provide_info', 'approve', 'return',
                 'claim', 'release', 'mark_urgent', 'mark_normal') then
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
  holder := r.assigned_to;
  prio   := r.priority;
  label  := public.admin_request_label(r.request_type);
  m_name := coalesce((select nullif(btrim(p.full_name), '') from public.profiles p where p.id = r.member_id), '');
  if m_name <> '' then
    about := ' لـ «' || m_name || '»';
  end if;

  -- ═ الاستلام والترك والأولوية (مسار الموافقات ٢): لا تغيّر المرحلة ولا مؤقتاتها ═
  if act in ('claim', 'release', 'mark_urgent', 'mark_normal') then
    if act = 'claim' then
      if cur in ('review', 'execute') then
        if not public.can_act_as_specialist(r) then
          raise exception 'استلام الطلب في هذه المرحلة للمختص' using errcode = '42501', hint = 'not_allowed';
        end if;
      elsif cur = 'approve' then
        if not is_mgr then
          raise exception 'استلام الطلب في مرحلة الاعتماد للمالك والمدير' using errcode = '42501', hint = 'not_allowed';
        end if;
      else
        raise exception 'الطلب ليس في المرحلة المناسبة لهذا الإجراء' using errcode = 'P0001', hint = 'wrong_stage';
      end if;
      if is_own and my_role <> 'owner' then
        raise exception 'لا يمكنك استلام طلبك — يتابعه مسؤول آخر' using errcode = '42501', hint = 'own_request';
      end if;
      if r.assigned_to is distinct from me then   -- استلامه مرة ثانية لا يغيّر شيئاً
        if r.assigned_to is not null and my_role <> 'owner' then
          perform public.approvals_raise_claimed(r.assigned_to);
        end if;
        prev   := r.assigned_to;
        holder := me;
        perform set_config('approvals.advance', 'on', true);
        update public.admin_requests set assigned_to = me, assigned_at = now() where id = r.id;
        perform set_config('approvals.advance', '', true);
        insert into public.admin_request_steps (request_id, actor_id, actor_role, action, note, subject_id)
        values (r.id, me, my_role, 'claim', case when prev is not null then 'أخذه المالك' end, prev);
      end if;
    elsif act = 'release' then
      if r.assigned_to is not null then           -- غير مستلَم: لا شيء
        if r.assigned_to is distinct from me and not is_mgr then
          raise exception 'ترك الطلب لمن استلمه أو للمالك والمدير' using errcode = '42501', hint = 'not_allowed';
        end if;
        prev   := r.assigned_to;
        holder := null;
        perform set_config('approvals.advance', 'on', true);
        update public.admin_requests set assigned_to = null, assigned_at = null where id = r.id;
        perform set_config('approvals.advance', '', true);
        insert into public.admin_request_steps (request_id, actor_id, actor_role, action, note, subject_id)
        values (r.id, me, my_role, 'release', case when prev <> me then 'أُلغي الاستلام' end,
                case when prev <> me then prev end);
      end if;
    else
      if not (public.can_act_as_specialist(r) or is_mgr) then
        raise exception 'تغيير الأولوية للمختص والمالك والمدير' using errcode = '42501', hint = 'not_allowed';
      end if;
      if is_own and my_role <> 'owner' then
        raise exception 'لا يمكنك تغيير أولوية طلبك' using errcode = '42501', hint = 'own_request';
      end if;
      prio := case when act = 'mark_urgent' then 'urgent' else 'normal' end;
      if prio is distinct from r.priority then
        perform set_config('approvals.advance', 'on', true);
        update public.admin_requests set priority = prio where id = r.id;
        perform set_config('approvals.advance', '', true);
        insert into public.admin_request_steps (request_id, actor_id, actor_role, action, note)
        values (r.id, me, my_role, 'priority', case when prio = 'urgent' then 'مستعجل' else 'عادي' end);
        -- المستعجل يُشعِر من بيده الطلب: المستلم، وإلا أصحاب المرحلة
        if prio = 'urgent' then
          targets := case when r.assigned_to is not null then array[r.assigned_to]
                          when cur = 'approve' then array(select public.approvals_manager_ids())
                          else array(select public.workflow_specialist_ids(r.request_type)) end;
          perform public.approvals_notify(targets, 'طلب مستعجل: ' || label, label || about || ' صار مستعجلاً',
            me, r.id, r.request_type, r.stage, 'priority');
        end if;
      end if;
    end if;
    return jsonb_build_object('request_id', r.id, 'stage', cur, 'assigned_to', holder, 'priority', prio);
  end if;

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
    -- المختص، أو المالك/المدير بعد التصعيد
    if not public.can_act_as_specialist(r) then
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

  -- الاستلام: الطلب عند غيرك (المختص في المراجعة، أو مدير آخر في الاعتماد) — المالك مستثنى
  if act <> 'provide_info' and my_role <> 'owner' and r.assigned_to is not null and r.assigned_to <> me then
    perform public.approvals_raise_claimed(r.assigned_to);
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
      v := btrim(coalesce(vals ->> f, ''));
      if v = '' then
        raise exception 'أدخل %', public.approvals_info_field_label(f) using errcode = '22023', hint = 'note_required';
      end if;
      if f = 'phone' then
        v := regexp_replace(translate(v, digits_a, digits_e), '[\s\-\(\)]', '', 'g');
        if v !~ '^\+?[0-9]{8,15}$' then
          raise exception 'رقم الهاتف غير صحيح — من ٨ إلى ١٥ رقماً' using errcode = '22023', hint = 'note_required';
        end if;
      elsif f in ('birth_date', 'death_date') then
        v := translate(v, digits_a, digits_e);
        if v !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
          raise exception '% غير صحيح — بصيغة سنة-شهر-يوم', public.approvals_info_field_label(f)
            using errcode = '22023', hint = 'note_required';
        end if;
        begin
          d := v::date;
        exception when others then
          raise exception '% غير صحيح', public.approvals_info_field_label(f) using errcode = '22023', hint = 'note_required';
        end;
        if d > today then
          raise exception '% لا يكون في المستقبل', public.approvals_info_field_label(f)
            using errcode = '22023', hint = 'note_required';
        end if;
      else
        v := left(regexp_replace(v, '\s+', ' ', 'g'), 200);
        if cardinality(string_to_array(v, ' ')) < 2 then
          raise exception 'اكتب الاسم الكامل (الاسم واسم الأب على الأقل)' using errcode = '22023', hint = 'note_required';
        end if;
      end if;
      reply := reply || jsonb_build_object(f, v);
      -- الرقم والتاريخ معزولان باتجاه اليسار لليمين (U+2066 … U+2069) فلا ينقلبان داخل السطر العربي
      step  := coalesce(step || E'\n', '') || public.approvals_info_field_label(f) || ': '
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

  -- التحديث (الحارس trg_zz_admin_request_workflow يسمح بأعمدة المسار داخل هذه الدالة فقط).
  -- كل تغيير مرحلة يصفّر التذكير والتصعيد؛ التوصية تفكّ الاستلام، والاعتماد/الإرجاع يعيدانه لمن أوصى إن بقي مختصاً.
  perform set_config('approvals.advance', 'on', true);
  if act in ('recommend_approve', 'recommend_reject') then
    nxt    := 'approve';
    holder := null;
    update public.admin_requests
       set stage = nxt, stage_since = now(),
           recommendation = case when act = 'recommend_approve' then 'approve' else 'reject' end,
           recommendation_note = note, recommended_by = me, recommended_at = now(),
           assigned_to = null, assigned_at = null, reminded_at = null, escalated_at = null
     where id = r.id;
  elsif act = 'request_info' then
    nxt := 'info';
    -- سؤال جديد: الرد السابق يبقى في سجل الخطوات فقط
    update public.admin_requests
       set stage = nxt, stage_since = now(), info_request = note, info_fields = fields, info_reply = null,
           reminded_at = null, escalated_at = null
     where id = r.id;
  elsif act = 'provide_info' then
    nxt := 'review';   -- السؤال والحقول تبقى للتاريخ، والرد في info_reply وملاحظة الخطوة
    update public.admin_requests
       set stage = nxt, stage_since = now(), info_reply = reply, reminded_at = null, escalated_at = null
     where id = r.id;
  else
    nxt    := case when act = 'approve' then 'execute' else 'review' end;
    holder := case when public.approvals_member_can_specialize(r.recommended_by, r.request_type) then r.recommended_by end;
    update public.admin_requests
       set stage = nxt, stage_since = now(),
           approved_by = case when act = 'approve' then me else approved_by end,
           approved_at = case when act = 'approve' then now() else approved_at end,
           approval_note = note,
           assigned_to = holder, assigned_at = case when holder is not null then now() end,
           reminded_at = null, escalated_at = null
     where id = r.id;
  end if;
  perform set_config('approvals.advance', '', true);

  insert into public.admin_request_steps (request_id, actor_id, actor_role, action, note)
  values (r.id, me, my_role, act, step);

  -- الإشعارات (كما كانت)
  if act in ('recommend_approve', 'recommend_reject') then
    perform public.approvals_notify(
      array(select public.approvals_manager_ids()),
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

  return jsonb_build_object('request_id', r.id, 'stage', nxt, 'assigned_to', holder, 'priority', prio);
end;
$function$;

-- ═══ ٦) الإدراج: مسح أعمدة المسار من المستخدم، المستعجل، المسار السريع ═══
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
    new.priority := 'normal'; new.assigned_to := null; new.assigned_at := null;
    new.reminded_at := null; new.escalated_at := null; new.fast_track := false;
  end if;
  if new.stage is null and new.status is not distinct from 'pending'
     and public.workflow_specialist_role(new.request_type) is not null
     and public.approvals_workflow_on() then
    new.stage := 'review';
    new.stage_since := now();
    -- بلاغ الوفاة مستعجل دائماً
    if new.request_type = 'deceased_report' then
      new.priority := 'urgent';
    end if;
    -- المسار السريع: مباشرة لمرحلة الاعتماد
    if exists (select 1 from public.app_settings s where new.request_type = any (s.approvals_fast_types)) then
      new.stage := 'approve';
      new.fast_track := true;
    end if;
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
declare
  label text;
  about text := '';
  mgrs  uuid[];
  sps   uuid[];
  title text;
begin
  if new.stage is not null and new.status is not distinct from 'pending' then
    insert into public.admin_request_steps (request_id, actor_id, actor_role, action)
    values (new.id, new.requester_id,
            (select case when p.status = 'active' then p.role when p.status in ('frozen', 'deleted') then p.status
                         else 'pending' end
             from public.profiles p where p.id = new.requester_id),
            'submitted');
    if new.fast_track then
      insert into public.admin_request_steps (request_id, actor_id, actor_role, action, note, created_at)
      values (new.id, null, 'system', 'fast_track', 'مسار سريع — مباشرة للمدير', now() + interval '1 millisecond');
    end if;

    -- المسار السريع يُشعِر المالك والمدير، والمستعجل يُشعِر المختص والمالك والمدير فوراً
    if (new.fast_track or new.priority = 'urgent') and public.approvals_workflow_on() then
      label := public.admin_request_label(new.request_type);
      select ' لـ «' || nullif(btrim(p.full_name), '') || '»' into about from public.profiles p where p.id = new.member_id;
      about := coalesce(about, '');
      mgrs  := array(select public.approvals_manager_ids());
      sps   := array(select x from public.workflow_specialist_ids(new.request_type) x where not (x = any (mgrs)));
      title := case when new.priority = 'urgent' then 'طلب مستعجل: ' || label else 'مسار سريع: ' || label end;
      if new.fast_track then
        perform public.approvals_notify(mgrs, title, 'مسار سريع — مباشرة للمدير: ' || label || about || ' بانتظار اعتمادك',
          new.requester_id, new.id, new.request_type, new.stage, 'fast_track');
        if new.priority = 'urgent' then
          perform public.approvals_notify(sps, title, label || about || ' — بمسار سريع عند المدير',
            new.requester_id, new.id, new.request_type, new.stage, 'submitted');
        end if;
      else
        perform public.approvals_notify(mgrs || sps, title, label || about || ' بانتظار المراجعة',
          new.requester_id, new.id, new.request_type, new.stage, 'submitted');
      end if;
    end if;
  end if;
  return new;
end;
$function$;

-- ═══ ٧) حارس التحديث: الأعمدة الجديدة محميّة، الاستلام في التنفيذ والاعتماد، والمصعَّد للمالك/المدير ═══
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
              new.info_fields, new.info_reply,
              new.priority, new.assigned_to, new.assigned_at, new.reminded_at, new.escalated_at, new.fast_track)
             is distinct from
             (old.stage, old.stage_since, old.recommendation, old.recommendation_note, old.recommended_by,
              old.recommended_at, old.info_request, old.approved_by, old.approved_at, old.approval_note,
              old.info_fields, old.info_reply,
              old.priority, old.assigned_to, old.assigned_at, old.reminded_at, old.escalated_at, old.fast_track);
  -- أي تعديل آخر (الرد، نقل المعرّفات عند الدمج، …) يمر كما هو
  if not closing and not changed then
    return new;
  end if;

  -- السيرفر وصيانة SQL والمهام (approvals_sla_tick)، وبلا دخول (سياسات الجدول ترفضه): لا فحص — ترتيب الإغلاق فقط
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

  -- إغلاق من مستخدم: أعمدة المسار من السيرفر لا من التطبيق (وتبقى للتاريخ)
  new.recommendation := old.recommendation; new.recommendation_note := old.recommendation_note;
  new.recommended_by := old.recommended_by; new.recommended_at := old.recommended_at;
  new.info_request := old.info_request; new.approved_by := old.approved_by;
  new.approved_at := old.approved_at; new.approval_note := old.approval_note;
  new.info_fields := old.info_fields; new.info_reply := old.info_reply;
  new.priority := old.priority; new.assigned_to := old.assigned_to; new.assigned_at := old.assigned_at;
  new.reminded_at := old.reminded_at; new.escalated_at := old.escalated_at; new.fast_track := old.fast_track;

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
      -- بعد اعتماد المدير: التنفيذ للمختص (أو المالك/المدير بعد التصعيد)، ولمن استلمه إن كان مستلَماً
      if not public.can_act_as_specialist(old) then
        raise exception 'تنفيذ الطلب للمختص بعد اعتماد المدير' using errcode = '42501', hint = 'not_allowed';
      end if;
      if my_role <> 'owner' and old.assigned_to is not null and old.assigned_to <> me then
        perform public.approvals_raise_claimed(old.assigned_to);
      end if;
    elsif cur = 'approve' and my_role in ('owner', 'admin') then
      -- تجاوز المدير: اعتماد وتنفيذ مباشر (طلب المالك ٢٠٢٦-١٠-١٥ «في قرارات يحتاج تجاوز»)
      if is_own and my_role <> 'owner' then
        raise exception 'لا يمكنك اعتماد طلبك — يعتمده مسؤول آخر' using errcode = '42501', hint = 'own_request';
      end if;
      if my_role <> 'owner' and old.assigned_to is not null and old.assigned_to <> me then
        perform public.approvals_raise_claimed(old.assigned_to);
      end if;
      direct := true;
      new.approved_by := me;
      new.approved_at := now();
    else
      raise exception 'الطلب يحتاج اعتماد المدير قبل التنفيذ' using errcode = 'P0001', hint = 'approval_needs_manager';
    end if;
  else
    -- الرفض النهائي للمدير في أي مرحلة؛ المختص يوصي بالرفض فقط. في «اعتماد» استلمه مدير آخر → له وحده (المالك مستثنى)
    if my_role not in ('owner', 'admin') then
      raise exception 'رفض الطلب للمالك والمدير — المختص يوصي بالرفض' using errcode = '42501', hint = 'not_allowed';
    end if;
    if cur = 'approve' and my_role <> 'owner' and old.assigned_to is not null and old.assigned_to <> me then
      perform public.approvals_raise_claimed(old.assigned_to);
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

-- ═══ ٨) المهلة والتصعيد (مهمة السيرفر كل ١٥ دقيقة) ═══
-- آمنة للتكرار: كل مرحلة تُذكَّر مرة وتُصعَّد مرة (reminded_at / escalated_at يُصفَّران مع تغيير المرحلة).
create or replace function public.approvals_sla_tick()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  r       public.admin_requests%rowtype;
  sla_n   integer;
  esc_n   integer;
  sla_u   integer;
  esc_u   integer;
  sla     integer;
  esc     integer;
  hrs     numeric;
  h       text;
  label   text;
  about   text;
  where_  text;
  n_rem   integer := 0;
  n_esc   integer := 0;
begin
  if not public.approvals_workflow_on() then
    return jsonb_build_object('reminded', 0, 'escalated', 0, 'skipped', 'workflow_off');
  end if;
  select min(s.approvals_sla_hours), min(s.approvals_escalate_hours),
         min(s.approvals_urgent_sla_hours), min(s.approvals_urgent_escalate_hours)
    into sla_n, esc_n, sla_u, esc_u
  from public.app_settings s;

  perform set_config('approvals.advance', 'on', true);
  for r in
    select * from public.admin_requests a
     where a.status = 'pending' and a.stage is not null
       and public.workflow_specialist_role(a.request_type) is not null
       and (a.reminded_at is null or (a.escalated_at is null and a.stage in ('review', 'execute')))
     order by a.stage_since nulls first
     for update skip locked
  loop
    hrs   := extract(epoch from (now() - coalesce(r.stage_since, r.created_at, now()))) / 3600.0;
    h     := floor(hrs)::integer::text;
    sla   := case when r.priority = 'urgent' then sla_u else sla_n end;
    esc   := case when r.priority = 'urgent' then esc_u else esc_n end;
    label := public.admin_request_label(r.request_type);
    about := coalesce((select ' لـ «' || nullif(btrim(p.full_name), '') || '»' from public.profiles p where p.id = r.member_id), '');

    if r.stage in ('review', 'execute') then
      where_ := case when r.stage = 'review' then 'المراجعة' else 'التنفيذ' end;
      if hrs >= sla and r.reminded_at is null then
        update public.admin_requests set reminded_at = now() where id = r.id;
        insert into public.admin_request_steps (request_id, actor_id, actor_role, action, note, subject_id)
        values (r.id, null, 'system', 'reminded', 'تذكير تلقائي بعد ' || h || ' ساعة', r.assigned_to);
        perform public.approvals_notify(
          case when r.assigned_to is not null then array[r.assigned_to]
               else array(select public.workflow_specialist_ids(r.request_type)) end,
          'تذكير: ' || label || ' متأخر', label || about || ' بانتظار ' || where_ || ' منذ ' || h || ' ساعة',
          null, r.id, r.request_type, r.stage, 'reminded');
        n_rem := n_rem + 1;
      end if;
      if hrs >= esc and r.escalated_at is null then
        update public.admin_requests set escalated_at = now(), assigned_to = null, assigned_at = null where id = r.id;
        insert into public.admin_request_steps (request_id, actor_id, actor_role, action, note, subject_id, created_at)
        values (r.id, null, 'system', 'escalated', 'تصعيد تلقائي بعد ' || h || ' ساعة', r.assigned_to,
                now() + interval '1 millisecond');
        perform public.approvals_notify(array(select public.approvals_manager_ids()),
          'تصعيد: ' || label || ' متأخر',
          label || about || ' متأخر في ' || where_ || ' منذ ' || h || ' ساعة — تقدر تتصرف بدل المختص',
          null, r.id, r.request_type, r.stage, 'escalated');
        n_esc := n_esc + 1;
      end if;
    elsif r.stage = 'approve' then
      if hrs >= sla and r.reminded_at is null then
        update public.admin_requests set reminded_at = now() where id = r.id;
        insert into public.admin_request_steps (request_id, actor_id, actor_role, action, note, subject_id)
        values (r.id, null, 'system', 'reminded', 'تذكير تلقائي بعد ' || h || ' ساعة', r.assigned_to);
        perform public.approvals_notify(
          case when r.assigned_to is not null then array[r.assigned_to]
               else array(select public.approvals_manager_ids()) end,
          'تذكير: ' || label || ' متأخر', label || about || ' بانتظار اعتمادك منذ ' || h || ' ساعة',
          null, r.id, r.request_type, r.stage, 'reminded');
        n_rem := n_rem + 1;
      end if;
    elsif r.stage = 'info' then
      if hrs >= 48 and r.reminded_at is null then
        update public.admin_requests set reminded_at = now() where id = r.id;
        insert into public.admin_request_steps (request_id, actor_id, actor_role, action, note)
        values (r.id, null, 'system', 'reminded', 'تذكير تلقائي لصاحب الطلب بعد ' || h || ' ساعة');
        perform public.approvals_notify(array[r.requester_id], 'تذكير: الإدارة تنتظر ردّك',
          'بخصوص ' || label || ': الإدارة تنتظر المعلومات المطلوبة منذ ' || h || ' ساعة',
          null, r.id, r.request_type, r.stage, 'reminded');
        n_rem := n_rem + 1;
      end if;
    end if;
  end loop;
  perform set_config('approvals.advance', '', true);

  return jsonb_build_object('reminded', n_rem, 'escalated', n_esc);
end;
$function$;

-- ═══ ٩) قوالب الردود ═══
create table if not exists public.approval_templates (
  id          uuid primary key default gen_random_uuid(),
  kind        text not null,
  body        text not null,
  sort        integer not null default 0,
  created_by  uuid default public.current_profile_id(),
  created_at  timestamptz default now(),
  constraint approval_templates_kind_check check (kind in ('reject', 'info', 'recommend', 'return', 'note')),
  constraint approval_templates_body_check check (char_length(body) between 1 and 300)
);
create index if not exists approval_templates_kind_idx on public.approval_templates (kind, sort);
comment on table public.approval_templates is
  'مسار الموافقات ٢: قوالب الردود الجاهزة (رفض، طلب معلومات، توصية، إرجاع، ملاحظة) — تقرؤها الإدارة ويعدّلها المالك والمدير';

alter table public.approval_templates enable row level security;
drop policy if exists approval_templates_select on public.approval_templates;
create policy approval_templates_select on public.approval_templates
  for select to authenticated
  using (public.current_user_role() = any (array['owner', 'admin', 'monitor', 'supervisor']));
drop policy if exists approval_templates_insert on public.approval_templates;
create policy approval_templates_insert on public.approval_templates
  for insert to authenticated
  with check (public.current_user_role() = any (array['owner', 'admin'])
              and (created_by is null or created_by = public.current_profile_id()));
drop policy if exists approval_templates_update on public.approval_templates;
create policy approval_templates_update on public.approval_templates
  for update to authenticated
  using (public.current_user_role() = any (array['owner', 'admin']))
  with check (public.current_user_role() = any (array['owner', 'admin']));
drop policy if exists approval_templates_delete on public.approval_templates;
create policy approval_templates_delete on public.approval_templates
  for delete to authenticated
  using (public.current_user_role() = any (array['owner', 'admin']));
revoke all on public.approval_templates from public, anon;
revoke truncate, references, trigger on public.approval_templates from authenticated;
grant select, insert, update, delete on public.approval_templates to authenticated;
grant all on public.approval_templates to service_role;

insert into public.approval_templates (kind, body, sort, created_by)
select v.kind, v.body, v.sort, null
from (values
  ('reject',    'الصورة غير واضحة، أرسل صورة أوضح',         1),
  ('reject',    'الاسم موجود في الشجرة من قبل',               2),
  ('reject',    'البيانات غير صحيحة',                         3),
  ('reject',    'الطلب مكرر',                                 4),
  ('info',      'نحتاج تاريخ الميلاد',                        1),
  ('info',      'أرسل رقم الهاتف الصحيح',                     2),
  ('info',      'وضّح صلة القرابة',                           3),
  ('recommend', 'تم التحقق من العائلة والبيانات صحيحة',       1),
  ('return',    'راجع البيانات مع صاحب الطلب',                1),
  ('note',      'تواصلت مع الأب وتأكدت',                      1)
) as v(kind, body, sort)
where not exists (select 1 from public.approval_templates t where t.kind = v.kind and t.body = v.body);

-- ═══ ١٠) الملاحظات الداخلية (للإدارة فقط — لا يراها صاحب الطلب ولا الأعضاء) ═══
create table if not exists public.admin_request_notes (
  id          uuid primary key default gen_random_uuid(),
  request_id  uuid not null references public.admin_requests(id) on delete cascade,
  author_id   uuid not null default public.current_profile_id(),
  body        text not null,
  created_at  timestamptz not null default now(),
  constraint admin_request_notes_body_check check (char_length(body) between 1 and 1000)
);
create index if not exists admin_request_notes_request_idx on public.admin_request_notes (request_id, created_at);
comment on table public.admin_request_notes is
  'مسار الموافقات ٢: ملاحظات داخلية على الطلب بين الإدارة — لا يراها صاحب الطلب ولا المعني به (إلا المالك)';

alter table public.admin_request_notes enable row level security;
-- القراءة والكتابة للإدارة الأربعة، ما عدا طلباتهم هم (صاحبه أو المعني به) — المالك يرى الكل
drop policy if exists admin_request_notes_select on public.admin_request_notes;
create policy admin_request_notes_select on public.admin_request_notes
  for select to authenticated
  using (public.current_user_role() = any (array['owner', 'admin', 'monitor', 'supervisor'])
         and (public.current_user_role() = 'owner'
              or not exists (select 1 from public.admin_requests r
                             where r.id = admin_request_notes.request_id
                               and (r.requester_id = any (array[auth.uid(), public.current_profile_id()])
                                    or r.member_id = any (array[auth.uid(), public.current_profile_id()])))));
drop policy if exists admin_request_notes_insert on public.admin_request_notes;
create policy admin_request_notes_insert on public.admin_request_notes
  for insert to authenticated
  with check (author_id = public.current_profile_id()
              and public.current_user_role() = any (array['owner', 'admin', 'monitor', 'supervisor'])
              and (public.current_user_role() = 'owner'
                   or not exists (select 1 from public.admin_requests r
                                  where r.id = admin_request_notes.request_id
                                    and (r.requester_id = any (array[auth.uid(), public.current_profile_id()])
                                         or r.member_id = any (array[auth.uid(), public.current_profile_id()])))));
drop policy if exists admin_request_notes_delete on public.admin_request_notes;
create policy admin_request_notes_delete on public.admin_request_notes
  for delete to authenticated
  using (author_id = public.current_profile_id()
         and public.current_user_role() = any (array['owner', 'admin', 'monitor', 'supervisor']));
revoke all on public.admin_request_notes from public, anon;
revoke update, truncate, references, trigger on public.admin_request_notes from authenticated;
grant select, insert, delete on public.admin_request_notes to authenticated;
grant all on public.admin_request_notes to service_role;

-- ملاحظة جديدة تُشعِر مستلم الطلب (إن وُجد ولم يكن الكاتب)
create or replace function public.notify_admin_request_note()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  r     public.admin_requests%rowtype;
  about text;
begin
  select * into r from public.admin_requests where id = new.request_id;
  if found and r.assigned_to is not null and r.assigned_to is distinct from new.author_id then
    about := coalesce((select ' لـ «' || nullif(btrim(p.full_name), '') || '»' from public.profiles p where p.id = r.member_id), '');
    perform public.approvals_notify(array[r.assigned_to],
      'ملاحظة داخلية على ' || public.admin_request_label(r.request_type) || about,
      public.approvals_first_name(new.author_id) || ': ' || left(new.body, 200),
      new.author_id, r.id, r.request_type, r.stage, 'note');
  end if;
  return null;
end;
$function$;

drop trigger if exists trg_admin_request_note_notify on public.admin_request_notes;
create trigger trg_admin_request_note_notify
  after insert on public.admin_request_notes
  for each row execute function public.notify_admin_request_note();

-- ═══ ١١) تقرير الأداء (المالك والمدير والمراقب) ═══
-- الطلبات المرسلة في الفترة [من، إلى) من أنواع المسار؛ متوسطات المراحل من الخطوات (مرحلة بدأت في الفترة
-- واكتملت، وتُستبعد الخطوات الآلية المتتالية أقل من ثانية)؛ عمل الإدارة من خطواتهم في الفترة.
create or replace function public.approvals_report(p_from timestamptz default null, p_to timestamptz default null)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  f       timestamptz := coalesce(p_from, now() - interval '30 days');
  t       timestamptz := coalesce(p_to, now());
  sla_n   integer;
  sla_u   integer;
  totals  jsonb;
  stages  jsonb;
  types   jsonb;
  staff   jsonb;
begin
  if coalesce(public.current_user_role(), '') not in ('owner', 'admin', 'monitor') then
    raise exception 'تقرير الموافقات للمالك والمدير والمراقب' using errcode = '42501', hint = 'not_allowed';
  end if;
  if f > t then
    raise exception 'بداية الفترة بعد نهايتها' using errcode = '22023', hint = 'bad_range';
  end if;
  select min(s.approvals_sla_hours), min(s.approvals_urgent_sla_hours) into sla_n, sla_u from public.app_settings s;

  with req as (
    select r.*, exists (select 1 from public.admin_request_steps s
                        where s.request_id = r.id and s.action = 'escalated') as was_escalated
    from public.admin_requests r
    where r.created_at >= f and r.created_at < t and public.workflow_specialist_role(r.request_type) is not null
  )
  select jsonb_build_object(
           'submitted',  count(*),
           'executed',   count(*) filter (where req.status = 'approved'),
           'rejected',   count(*) filter (where req.status = 'rejected'),
           'pending',    count(*) filter (where req.status = 'pending'),
           'urgent',     count(*) filter (where req.priority = 'urgent'),
           'escalated',  count(*) filter (where req.was_escalated),
           'fast_track', count(*) filter (where req.fast_track),
           'overdue_now', (select count(*) from public.admin_requests o
                           where o.status = 'pending' and o.stage is not null
                             and public.workflow_specialist_role(o.request_type) is not null
                             and now() - coalesce(o.stage_since, o.created_at)
                                 >= make_interval(hours => case when o.stage = 'info' then 48
                                                                when o.priority = 'urgent' then sla_u
                                                                else sla_n end)))
    into totals
  from req;

  with seg as (
    select s.created_at as started,
           lead(s.created_at) over (partition by s.request_id order by s.created_at, s.id) as ended,
           case s.action when 'submitted' then 'review' when 'provide_info' then 'review' when 'return' then 'review'
                         when 'fast_track' then 'approve' when 'recommend_approve' then 'approve'
                         when 'recommend_reject' then 'approve' when 'request_info' then 'info'
                         when 'approve' then 'execute' end as stage
    from public.admin_request_steps s
    where s.action in ('submitted', 'fast_track', 'request_info', 'provide_info', 'recommend_approve',
                       'recommend_reject', 'approve', 'return', 'executed', 'rejected')
  ), done as (
    select seg.stage, extract(epoch from (seg.ended - seg.started)) / 3600.0 as h
    from seg
    where seg.stage is not null and seg.ended is not null and seg.started >= f and seg.started < t
      and seg.ended - seg.started >= interval '1 second'
  )
  select jsonb_build_object(
           'review_hours',  round((avg(done.h) filter (where done.stage = 'review'))::numeric, 1),
           'approve_hours', round((avg(done.h) filter (where done.stage = 'approve'))::numeric, 1),
           'execute_hours', round((avg(done.h) filter (where done.stage = 'execute'))::numeric, 1),
           'info_hours',    round((avg(done.h) filter (where done.stage = 'info'))::numeric, 1))
    into stages
  from done;

  select coalesce(jsonb_agg(jsonb_build_object('type', x.request_type, 'label', public.admin_request_label(x.request_type),
                                               'count', x.n, 'executed', x.e, 'rejected', x.j)
                            order by x.n desc, x.request_type), '[]'::jsonb)
    into types
  from (select r.request_type, count(*) as n,
               count(*) filter (where r.status = 'approved') as e,
               count(*) filter (where r.status = 'rejected') as j
        from public.admin_requests r
        where r.created_at >= f and r.created_at < t and public.workflow_specialist_role(r.request_type) is not null
        group by r.request_type) x;

  with chg as (
    select s.actor_id, s.action, s.created_at,
           lag(s.created_at) over (partition by s.request_id order by s.created_at, s.id) as prev_at
    from public.admin_request_steps s
    where s.action in ('submitted', 'fast_track', 'request_info', 'provide_info', 'recommend_approve',
                       'recommend_reject', 'approve', 'return', 'executed', 'rejected')
  ), acts as (
    select s.actor_id, count(*) as n
    from public.admin_request_steps s
    where s.actor_id is not null and s.created_at >= f and s.created_at < t
      and s.action in ('recommend_approve', 'recommend_reject', 'request_info', 'approve', 'return',
                       'executed', 'rejected', 'claim', 'release', 'priority')
    group by s.actor_id
  ), resp as (
    select c.actor_id, avg(extract(epoch from (c.created_at - c.prev_at)) / 3600.0) as h
    from chg c
    where c.actor_id is not null and c.created_at >= f and c.created_at < t and c.prev_at is not null
      and c.action in ('recommend_approve', 'recommend_reject', 'request_info', 'approve', 'return', 'executed', 'rejected')
      and c.created_at - c.prev_at >= interval '1 second'
    group by c.actor_id
  ), esc as (
    select s.subject_id as actor_id, count(*) as n
    from public.admin_request_steps s
    where s.action = 'escalated' and s.subject_id is not null and s.created_at >= f and s.created_at < t
    group by s.subject_id
  ), ids as (
    select acts.actor_id from acts union select esc.actor_id from esc
  )
  select coalesce(jsonb_agg(jsonb_build_object(
             'member_id', i.actor_id,
             'name', coalesce(nullif(btrim(p.full_name), ''), p.first_name),
             'role', p.role,
             'actions', coalesce(a.n, 0),
             'avg_response_hours', round(rs.h::numeric, 1),
             'escalations', coalesce(e.n, 0))
           order by coalesce(a.n, 0) desc, coalesce(e.n, 0) desc, coalesce(p.full_name, '')), '[]'::jsonb)
    into staff
  from ids i
  left join public.profiles p on p.id = i.actor_id
  left join acts a on a.actor_id = i.actor_id
  left join resp rs on rs.actor_id = i.actor_id
  left join esc e on e.actor_id = i.actor_id;

  return jsonb_build_object(
    'period', jsonb_build_object('from', f, 'to', t),
    'totals', totals,
    'stages', stages,
    'types', types,
    'staff', staff);
end;
$function$;

-- ═══ ١٢) الجدولة (pg_cron) — cron.schedule بالاسم نفسه يحدّث المهمة بدل تكرارها ═══
select cron.schedule('approvals-sla', '*/15 * * * *', 'select public.approvals_sla_tick()');

-- ═══ ١٣) الصلاحيات ═══
revoke all on function public.advance_admin_request(uuid, text, text, text[], jsonb) from public, anon;
grant execute on function public.advance_admin_request(uuid, text, text, text[], jsonb) to authenticated;
revoke all on function public.approvals_report(timestamptz, timestamptz) from public, anon;
grant execute on function public.approvals_report(timestamptz, timestamptz) to authenticated;
revoke all on function public.can_act_as_specialist(uuid) from public, anon;
grant execute on function public.can_act_as_specialist(uuid) to authenticated;
revoke all on function public.can_act_as_specialist(public.admin_requests) from public, anon;
grant execute on function public.can_act_as_specialist(public.admin_requests) to authenticated;
-- داخلية فقط
revoke all on function public.approvals_sla_tick() from public, anon, authenticated;
revoke all on function public.approvals_manager_ids() from public, anon, authenticated;
revoke all on function public.approvals_member_can_specialize(uuid, text) from public, anon, authenticated;
revoke all on function public.approvals_first_name(uuid) from public, anon, authenticated;
revoke all on function public.approvals_raise_claimed(uuid) from public, anon, authenticated;
revoke all on function public.notify_admin_request_note() from public, anon, authenticated;
