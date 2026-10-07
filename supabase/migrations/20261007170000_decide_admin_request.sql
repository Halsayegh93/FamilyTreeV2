-- الموافقات من السيرفر: decide_admin_request (فحص الثغرات ٢٠٢٦-١٠-٠٤ البند أ-٣ — موافقة المالك ٢٠٢٦-١٠-٠٧)
--
-- كان قرار «قبول/رفض» طلب المراجعة يُنفَّذ في التطبيق: يعيد فحص «معلّق»، يكتب التعديل، يرسل
-- الإشعارات، ثم يغلق الطلب — طلبات شبكة منفصلة (كتابة ناقصة عند الانقطاع، وموافقتان متزامنتان
-- تطبّقان مرتين). هذه الدالة تفعل الشيء نفسه **بلا سلوك جديد** في معاملة واحدة:
--   ١) صلاحية المتصل لنوع الطلب = can_handle_admin_request (كسياسة admin_requests_update_by_scope)،
--      وطلبك أنت يعالجه غيرك إلا المالك.
--   ٢) قفل الصف (for update) وشرط «معلّق».
--   ٣) نفس كتابات الآيفون اليوم لكل نوع/إجراء (AdminRequestViewModel.swift) — الجدول الكامل في
--      docs/approvals-server-2026-10-07.md.
--   ٤) إغلاق الطلب ثم الإشعارات نفسها (صاحب الطلب للمالك/المدير فقط كما يفعل sendNotification،
--      وإعلان الإدارة target = NULL) — الدفع يخرج من trg_push_on_notification كما اليوم.
--   ٥) ترجع jsonb: admin_push (للتطبيق يرسله إلى push-admins كما اليوم)، death_announcement (مربّع
--      «إعلان وفاة»)، storage_cleanup (ملف اقتراح الصورة — الحذف المباشر من storage ممنوع)، new_member_id.
-- الحراس الحالية (أدوار، أعمدة حساسة، روابط العائلة، حذف المالك، توحيد الرقم) تعمل كما هي: تقرأ
-- هوية المتصل من الـ JWT لا من مالك الدالة. لا يُسحب أي مسار قديم الآن (النسخ القديمة تكتب مباشرة).
-- الأنواع: tree_edit, deceased_report, child_add, name_change, family_change, phone_change,
--          photo_suggestion, news_report, content_report. الانضمام/الربط/التواصل تبقى في التطبيقات.
--
-- التراجع: supabase/rollback/20261007170000_decide_admin_request_rollback.sql
-- التجربة: supabase/tests/family_links/decide_admin_request.test.mjs

create or replace function public.decide_admin_request(
  p_request_id uuid,
  p_decision   text,
  p_reason     text  default null,
  p_overrides  jsonb default null
)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  uid         uuid := auth.uid();
  me          uuid := public.current_profile_id();
  my_role     text := coalesce(public.current_user_role(), 'pending');
  r           public.admin_requests%rowtype;
  decision    text := lower(btrim(coalesce(p_decision, '')));
  approving   boolean;
  silent      boolean := false;
  reason      text := nullif(regexp_replace(coalesce(p_reason, ''), '^\s+|\s+$', '', 'g'), '');
  suffix      text := '';
  m_name      text;          -- request.member?.fullName
  d           jsonb;         -- TreeEditPayload كما يقرؤه الآيفون، أو null
  act         text;          -- resolvedAction
  label       text;          -- arabicLabel
  t_name      text;          -- targetMemberName ?? member.fullName
  tgt         uuid;
  par         uuid;
  v_text      text;
  v_date      date;
  v_first     text;
  v_json      jsonb;
  par_full    text;
  par_found   boolean;
  was_dead    boolean;
  is_female   boolean;
  t_full      text;
  t_found     boolean;
  child_id    uuid;
  child_first text;
  v_phone     text;
  v_path      text;
  n_title     text;          -- إشعار صاحب الطلب
  n_body      text;
  n_kind      text := 'admin';
  b_title     text;          -- إعلان الإدارة
  b_body      text;
  b_kind      text;
  notified    boolean := false;
  death       jsonb;
  cleanup     jsonb;
  new_id      uuid;
  uuid_re     constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
begin
  if uid is null or me is null then
    raise exception 'not_authenticated' using errcode = '42501', hint = 'not_authenticated';
  end if;
  if decision not in ('approve', 'reject') then
    raise exception 'bad_decision' using errcode = '22023', hint = 'bad_decision';
  end if;
  approving := decision = 'approve';
  if p_overrides is not null then
    if jsonb_typeof(p_overrides) <> 'object'
       or exists (select 1 from jsonb_object_keys(p_overrides) k where k <> 'silent')
       or coalesce(jsonb_typeof(p_overrides->'silent'), 'boolean') <> 'boolean' then
      raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload', detail = 'overrides';
    end if;
    silent := coalesce((p_overrides->>'silent')::boolean, false);
  end if;
  if reason is not null then
    suffix := E'\nالسبب: ' || reason;
  end if;

  select * into r from public.admin_requests where id = p_request_id for update;
  if not found then
    raise exception 'request_not_found' using errcode = 'P0002', hint = 'request_not_found';
  end if;
  if coalesce(r.request_type, '') not in ('tree_edit', 'deceased_report', 'child_add', 'name_change',
       'family_change', 'phone_change', 'photo_suggestion', 'news_report', 'content_report') then
    raise exception 'unsupported_type' using errcode = '22023', hint = 'unsupported_type';
  end if;
  if not public.can_handle_admin_request(r.request_type) then
    raise exception 'not_allowed' using errcode = '42501', hint = 'not_allowed';
  end if;
  if my_role <> 'owner' and (r.requester_id = any (array[uid, me]) or r.member_id = any (array[uid, me])) then
    raise exception 'own_request' using errcode = '42501', hint = 'own_request';
  end if;
  if r.status is distinct from 'pending' then
    raise exception 'already_handled' using errcode = 'P0001', hint = 'already_handled';
  end if;
  -- «بلا إشعارات» للقبول الجماعي لإضافة الأبناء فقط (كما يفعل bulkApproveChildAddRequests)
  if silent and not (approving and r.request_type = 'child_add') then
    raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload', detail = 'silent';
  end if;

  m_name := coalesce((select p.full_name from public.profiles p where p.id = r.member_id), '');

  -- ═══ تعديل الشجرة ═══
  if r.request_type = 'tree_edit' then
    begin
      d := r.details::jsonb;
    exception when others then
      d := null;
    end;
    if d is not null and jsonb_typeof(d) <> 'object' then
      d := null;
    end if;
    -- JSONDecoder في الآيفون: v رقم وaction نص، وباقي الحقول نصوص (أو غائبة) — غير ذلك = حمولة غير مقروءة
    if d is not null and (jsonb_typeof(d->'v') is distinct from 'number'
        or jsonb_typeof(d->'action') is distinct from 'string'
        or coalesce(jsonb_typeof(d->'isAdminDirectEdit'), 'null') not in ('boolean', 'null')
        or exists (select 1 from jsonb_each(d) e
                   where e.key in ('targetMemberId', 'targetMemberName', 'newName', 'newPhone', 'newBirthDate',
                                   'deathDate', 'newPhotoUrl', 'parentMemberId', 'parentMemberName',
                                   'newMemberName', 'reason', 'notes')
                     and jsonb_typeof(e.value) not in ('string', 'null'))) then
      d := null;
    end if;
    act := case d->>'action' when 'إضافة' then 'add' when 'تعديل اسم' then 'edit_name' when 'حذف' then 'delete'
           else d->>'action' end;
    if act not in ('add', 'edit_name', 'edit_phone', 'edit_birth', 'deceased', 'add_death_date', 'add_photo',
                   'delete', 'other') then
      act := null;
    end if;
    label := case act when 'add' then 'إضافة' when 'edit_name' then 'تعديل اسم' when 'edit_phone' then 'تعديل رقم'
             when 'edit_birth' then 'تعديل ميلاد' when 'deceased' then 'تسجيل وفاة'
             when 'add_death_date' then 'إضافة تاريخ وفاة' when 'add_photo' then 'إضافة صورة'
             when 'delete' then 'حذف' when 'other' then 'طلب آخر' end;
    t_name := coalesce(d->>'targetMemberName', m_name);

    -- المستهدف: يُقرأ فقط حين يكتب الإجراء (معرّف غير صالح = خطأ كما في PostgREST)
    if act in ('edit_name', 'edit_phone', 'deceased', 'delete', 'edit_birth', 'add_death_date', 'add_photo', 'other')
       and d->>'targetMemberId' is not null and d->>'targetMemberId' ~ uuid_re then
      tgt := (d->>'targetMemberId')::uuid;
    end if;

    if approving then
      n_body := 'تم قبول طلب تعديل الشجرة';
      if act = 'edit_name' then
        v_text := regexp_replace(coalesce(d->>'newName', ''), '^\s+|\s+$', '', 'g');
        if d->>'targetMemberId' is not null and v_text <> '' then
          if tgt is null then raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload', detail = 'targetMemberId'; end if;
          update public.profiles set full_name = v_text, first_name = coalesce((regexp_match(v_text, '\S+'))[1], v_text)
           where id = tgt;
          n_body := 'تم تغيير الاسم إلى: «' || v_text || '»';
        end if;
      elsif act = 'edit_phone' then
        v_text := d->>'newPhone';
        if d->>'targetMemberId' is not null and coalesce(v_text, '') <> '' then
          if tgt is null then raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload', detail = 'targetMemberId'; end if;
          update public.profiles set phone_number = v_text where id = tgt;
          n_body := 'تم تحديث رقم الهاتف' || case when t_name = '' then '' else ' لـ «' || t_name || '»' end;
        end if;
      elsif act = 'deceased' then
        if d->>'targetMemberId' is not null then
          if tgt is null then raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload', detail = 'targetMemberId'; end if;
          v_text := d->>'deathDate';
          if coalesce(v_text, '') <> '' then
            begin
              v_date := v_text::date;
            exception when others then
              raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload', detail = 'deathDate';
            end;
          end if;
          select coalesce(p.is_deceased, false), lower(coalesce(p.gender, '')) = 'female', coalesce(p.full_name, '')
            into was_dead, is_female, t_full from public.profiles p where p.id = tgt;
          t_found := found;
          update public.profiles
             set is_deceased = true,
                 death_date = case when coalesce(v_text, '') <> '' then v_date else death_date end
           where id = tgt;
          -- وفاة جديدة (كان حياً) → مربّع «إعلان وفاة» في التطبيق
          if t_found and not was_dead then
            death := jsonb_build_object('member_id', tgt, 'name', case when t_name = '' then t_full else t_name end,
                                        'is_female', is_female, 'death_date', d->'deathDate');
          end if;
          n_body := 'تم تأكيد حالة الوفاة' || case when t_name = '' then '' else ' لـ «' || t_name || '»' end;
        end if;
      elsif act = 'delete' then
        if d->>'targetMemberId' is not null then
          if tgt is null then raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload', detail = 'targetMemberId'; end if;
          update public.profiles set is_hidden_from_tree = true where id = tgt;
          n_body := 'تم قبول طلب حذف' || case when t_name = '' then '' else ' «' || t_name || '»' end || ' من الشجرة';
        end if;
      elsif act = 'add' then
        v_text := regexp_replace(coalesce(d->>'newMemberName', ''), '^\s+|\s+$', '', 'g');
        if d->>'parentMemberId' is not null and v_text <> '' then
          if d->>'parentMemberId' !~ uuid_re then
            raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload', detail = 'parentMemberId';
          end if;
          par := (d->>'parentMemberId')::uuid;
          v_first := coalesce((regexp_match(v_text, '\S+'))[1], v_text);
          select coalesce(p.full_name, '') into par_full from public.profiles p where p.id = par;
          par_found := found;
          new_id := gen_random_uuid();
          insert into public.profiles (id, first_name, full_name, father_id, role, status, is_phone_hidden, sort_order)
          values (new_id, v_first, case when par_found then v_first || ' ' || par_full else v_text end, par,
                  'member', 'active', true, 0);
          n_body := 'تم إضافة «' || v_first || '» تحت «'
                    || coalesce(d->>'parentMemberName', case when par_found then par_full end, '') || '»';
        end if;
      elsif act = 'edit_birth' then
        v_text := regexp_replace(coalesce(d->>'newBirthDate', d->>'newName', ''), '^\s+|\s+$', '', 'g');
        if d->>'targetMemberId' is not null and v_text <> '' then
          if tgt is null then raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload', detail = 'targetMemberId'; end if;
          begin
            v_date := v_text::date;
          exception when others then
            raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload', detail = 'newBirthDate';
          end;
          update public.profiles set birth_date = v_date where id = tgt;
          n_body := 'تم تحديث تاريخ الميلاد إلى: «' || v_text || '»';
        end if;
      elsif act = 'add_death_date' then
        v_text := regexp_replace(coalesce(d->>'deathDate', ''), '^\s+|\s+$', '', 'g');
        if d->>'targetMemberId' is not null and v_text <> '' then
          if tgt is null then raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload', detail = 'targetMemberId'; end if;
          begin
            v_date := v_text::date;
          exception when others then
            raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload', detail = 'deathDate';
          end;
          update public.profiles set is_deceased = true, death_date = v_date where id = tgt;
          n_body := 'تم إضافة تاريخ الوفاة' || case when t_name = '' then '' else ' لـ «' || t_name || '»' end;
        end if;
      elsif act = 'add_photo' then
        v_text := regexp_replace(coalesce(d->>'newPhotoUrl', ''), '^\s+|\s+$', '', 'g');
        -- لا يُقبل إلا رابط من تخزين المشروع (كما في الآيفون)
        if d->>'targetMemberId' is not null and v_text <> ''
           and position('/storage/v1/object/public/avatars/' in v_text) > 0 then
          if tgt is null then raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload', detail = 'targetMemberId'; end if;
          update public.profiles set avatar_url = v_text where id = tgt;
          n_body := 'تم اعتماد الصورة' || case when t_name = '' then '' else ' لـ «' || t_name || '»' end;
        end if;
      elsif act = 'other' then
        -- تعديلات الملف بعد تجاوز حد الـ٣ (reason = profile_*) تُطبَّق؛ غيرها يُعلِم العضو فقط
        if d->>'targetMemberId' is not null and left(coalesce(d->>'reason', ''), 8) = 'profile_'
           and d->>'newName' is not null then
          v_text := d->>'newName';
          if d->>'reason' in ('profile_bio', 'profile_phone_hidden', 'profile_marital') and tgt is null then
            raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload', detail = 'targetMemberId';
          end if;
          if d->>'reason' = 'profile_bio' then
            -- [BioStation] كما يقرؤه الآيفون (id uuid، title/details نص، year نص أو غائب) — وإلا []
            begin
              v_json := v_text::jsonb;
            exception when others then
              v_json := null;
            end;
            if v_json is not null and jsonb_typeof(v_json) = 'array' and not exists (
                 select 1 from jsonb_array_elements(v_json) e(x)
                 where jsonb_typeof(x) is distinct from 'object'
                    or jsonb_typeof(x->'id') is distinct from 'string' or (x->>'id') !~ uuid_re
                    or jsonb_typeof(x->'title') is distinct from 'string'
                    or jsonb_typeof(x->'details') is distinct from 'string'
                    or coalesce(jsonb_typeof(x->'year'), 'null') not in ('string', 'null')) then
              v_json := (select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                           'id', upper(x->>'id'), 'year', x->'year', 'title', x->'title', 'details', x->'details'))
                           order by o), '[]'::jsonb)
                         from jsonb_array_elements(v_json) with ordinality e(x, o));
            else
              v_json := '[]'::jsonb;
            end if;
            update public.profiles set bio_json = v_json where id = tgt;
            n_body := 'تم اعتماد تعديل النبذة';
          elsif d->>'reason' = 'profile_phone_hidden' then
            update public.profiles set is_phone_hidden = (v_text = 'true') where id = tgt;
            n_body := 'تم اعتماد تعديل إظهار الرقم';
          elsif d->>'reason' = 'profile_marital' then
            update public.profiles set is_married = (v_text = 'true') where id = tgt;
            n_body := 'تم اعتماد تعديل الحالة الاجتماعية';
          else
            n_body := 'تم قبول طلبك';
          end if;
        else
          n_body := 'تم قبول طلبك' || case when t_name = '' then '' else ' «' || t_name || '»' end;
        end if;
      end if;
      n_title := 'تم قبول طلبك';
      b_title := 'تم قبول ' || coalesce(label, 'تعديل');
      b_body  := 'تم قبول طلب ' || coalesce(label, 'تعديل') || case when t_name = '' then '' else ' لـ «' || t_name || '»' end;
    else
      label   := coalesce(label, 'التعديل');
      n_title := 'لم يتم قبول طلبك';
      n_body  := 'تم رفض طلب ' || label || case when t_name = '' then '' else E'\n«' || t_name || '»' end || suffix;
      n_kind  := 'request_rejected';
      b_title := 'تم رفض ' || label;
      b_body  := 'تم رفض طلب ' || label || case when t_name = '' then '' else ' لـ «' || t_name || '»' end;
    end if;
    b_kind := 'tree_edit';

  -- ═══ تأكيد وفاة ═══
  elsif r.request_type = 'deceased_report' then
    if approving then
      select coalesce(p.is_deceased, false), lower(coalesce(p.gender, '')) = 'female', coalesce(p.full_name, '')
        into was_dead, is_female, t_full from public.profiles p where p.id = r.member_id;
      t_found := found;
      update public.profiles set is_deceased = true where id = r.member_id;
      if t_found and not was_dead then
        death := jsonb_build_object('member_id', r.member_id, 'name', case when m_name = '' then t_full else m_name end,
                                    'is_female', is_female, 'death_date', null);
      end if;
      n_title := 'تم قبول طلبك';
      n_body  := 'تم تأكيد حالة الوفاة وتحديث الشجرة';
      b_title := 'تم قبول طلب وفاة';
      b_body  := case when m_name = '' then 'تم تأكيد حالة وفاة' else 'تم تأكيد وفاة «' || m_name || '»' end;
    else
      b_title := 'تم رفض طلب وفاة';
      b_body  := case when m_name = '' then 'تم رفض طلب تأكيد وفاة' else 'تم رفض طلب تأكيد وفاة «' || m_name || '»' end || suffix;
    end if;
    b_kind := 'deceased_report';

  -- ═══ إضافة ابن (الطلب عن الأب member_id، والابن new_value) ═══
  elsif r.request_type = 'child_add' then
    if r.new_value ~ uuid_re then
      child_id := r.new_value::uuid;
    elsif not approving and r.new_value is not null then
      raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload', detail = 'new_value';
    end if;
    child_first := coalesce((select p.first_name from public.profiles p where p.id = child_id), '');
    if approving then
      -- ابن أضافه عضو يُحفظ «معلّقاً» — القبول يفعّله؛ المفعّل والمجمّد لا يتغيّران
      if child_id is not null then
        update public.profiles set status = 'active' where id = child_id and status = 'pending';
      end if;
      n_title := 'تم قبول طلبك';
      n_body  := 'تم إضافة الابن: «' || child_first || '» لـ: «' || m_name || '»';
      b_title := 'تم قبول طلب إضافة ابن';
      b_body  := 'تم إضافة «' || child_first || '» لـ «' || m_name || '»';
    else
      -- الرفض يحذف ملف الابن — للمالك والمدير (سياسة profiles_delete_admin_or_owner؛ للمراقب لا يُحذف شيء كاليوم)
      if child_id is not null and my_role in ('owner', 'admin') then
        delete from public.profiles where id = child_id;
      end if;
      b_title := 'تم رفض طلب إضافة ابن';
      b_body  := case when child_first = '' then 'تم رفض طلب إضافة ابن' else 'تم رفض طلب إضافة «' || child_first || '»' end || suffix;
    end if;
    b_kind := 'child_add';

  -- ═══ تغيير الاسم / العائلة ═══
  elsif r.request_type in ('name_change', 'family_change') then
    if approving then
      if coalesce(r.new_value, '') = '' then
        raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload', detail = 'new_value';
      end if;
      if r.request_type = 'family_change' then
        perform public.set_family_name_cascade(r.member_id, r.new_value);
        n_title := 'تم تغيير عائلتك';
        n_body  := 'تم اعتماد عائلتك الجديدة: ' || r.new_value;
      else
        update public.profiles
           set full_name = r.new_value, first_name = coalesce((regexp_match(r.new_value, '\S+'))[1], r.new_value)
         where id = r.member_id;
        n_title := 'تم تغيير اسمك';
        n_body  := 'تم اعتماد اسمك الجديد: ' || r.new_value;
        b_title := 'تم قبول تغيير اسم';
        b_body  := case when m_name = '' then 'وافقت الإدارة — تم اعتماد الاسم الجديد: «' || r.new_value || '»'
                        else 'وافقت الإدارة — تغيّر الاسم من «' || m_name || '» إلى «' || r.new_value || '»' end;
        b_kind  := 'name_change';
      end if;
    else
      n_title := 'لم يتم قبول طلبك';
      n_body  := case when r.request_type = 'family_change' then 'طلب تغيير العائلة لم تتم الموافقة عليه'
                      else 'طلب تغيير الاسم لم تتم الموافقة عليه' end || suffix;
      n_kind  := 'request_rejected';
      b_title := 'تم رفض تغيير اسم';
      b_body  := case when m_name = '' then 'تم رفض طلب تغيير الاسم' else 'تم رفض طلب تغيير اسم «' || m_name || '»' end;
      b_kind  := 'name_change';
    end if;

  -- ═══ تغيير الرقم ═══
  elsif r.request_type = 'phone_change' then
    if approving then
      v_phone := public.normalize_kuwait_phone(r.new_value);
      if v_phone is null then
        raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload', detail = 'new_value';
      end if;
      -- رقم لعضو آخر (آخر ٨ أرقام، كفحص isPhoneDuplicate — ويشمل الأرقام المخفية)
      if exists (select 1 from public.profiles p
                 where p.id <> r.member_id and coalesce(p.phone_number, '') <> ''
                   and length(regexp_replace(p.phone_number, '[^0-9]', '', 'g')) >= 8
                   and right(regexp_replace(p.phone_number, '[^0-9]', '', 'g'), 8)
                       = right(regexp_replace(v_phone, '[^0-9]', '', 'g'), 8)) then
        raise exception 'phone_in_use' using errcode = 'P0001', hint = 'phone_in_use';
      end if;
      update public.profiles set phone_number = v_phone where id = r.member_id;
      n_title := 'تم تغيير رقم هاتفك';
      n_body  := 'رقم هاتفك الجديد تم اعتماده بنجاح';
      b_title := 'تم قبول تغيير رقم';
      b_body  := case when m_name = '' then 'تم قبول طلب تغيير رقم' else 'تم تغيير رقم «' || m_name || '»' end;
    else
      n_title := 'لم يتم قبول طلبك';
      n_body  := 'طلب تغيير رقم الهاتف لم تتم الموافقة عليه' || suffix;
      n_kind  := 'request_rejected';
      b_title := 'تم رفض تغيير رقم';
      b_body  := case when m_name = '' then 'تم رفض طلب تغيير رقم' else 'تم رفض تغيير رقم «' || m_name || '»' end;
    end if;
    b_kind := 'phone_change';

  -- ═══ اقتراح صورة (النوع القديم) ═══
  elsif r.request_type = 'photo_suggestion' then
    if approving then
      if coalesce(r.new_value, '') = '' then
        raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload', detail = 'new_value';
      end if;
      update public.profiles
         set avatar_url = r.new_value || case when position('?' in r.new_value) > 0 then '&' else '?' end
                          || 'v=' || floor(extract(epoch from now()))::bigint
       where id = r.member_id;
      n_title := 'تم قبول اقتراحك';
      n_body  := 'الصورة المقترحة تم قبولها وتحديثها';
    else
      -- حذف الملف عبر Storage API في التطبيق — ملفات الاقتراح فقط
      v_path := substring(coalesce(r.new_value, '') from '/storage/v1/object/public/avatars/([^?#]+)');
      if left(coalesce(v_path, ''), 17) = 'photo_suggestion_' then
        cleanup := jsonb_build_object('bucket', 'avatars', 'paths', jsonb_build_array(v_path));
      end if;
      n_title := 'لم يتم قبول طلبك';
      n_body  := 'اقتراح الصورة لم تتم الموافقة عليه' || suffix;
      n_kind  := 'request_rejected';
    end if;

  -- ═══ البلاغات ═══
  else
    if approving then
      -- قبول بلاغ خبر يحذف الخبر؛ بلاغ المحتوى لا يشير لخبر (حارس الإدراج) فلا يُحذف شيء
      if r.request_type = 'news_report' and r.new_value ~ uuid_re then
        delete from public.news where id = r.new_value::uuid;
      end if;
      n_title := 'تمت مراجعة بلاغك';
      n_body  := 'بلاغك تم مراجعته واتخاذ الإجراء المناسب';
    end if;
  end if;

  update public.admin_requests set status = case when approving then 'approved' else 'rejected' end where id = r.id;

  if not silent then
    -- صاحب الطلب: المالك/المدير فقط (حارس sendNotification في الآيفون)
    if n_title is not null and my_role in ('owner', 'admin') and r.requester_id is not null
       and exists (select 1 from public.profiles p where p.id = r.requester_id) then
      insert into public.notifications (target_member_id, title, body, kind, created_by)
      values (r.requester_id, n_title, n_body, n_kind, me);
      notified := true;
    end if;
    -- إعلان الإدارة (يوزّعه fanout_broadcast_notification نسخةً لكل إداري)
    if b_title is not null then
      insert into public.notifications (target_member_id, title, body, kind, created_by)
      values (null, b_title, b_body, b_kind, me);
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'request_id', r.id,
    'request_type', r.request_type,
    'status', case when approving then 'approved' else 'rejected' end,
    'action', act,
    'requester_notified', notified,
    'admin_push', case when b_title is not null and not silent
                       then jsonb_build_object('title', b_title, 'body', b_body, 'kind', b_kind) end,
    'death_announcement', death,
    'storage_cleanup', cleanup,
    'new_member_id', new_id);
end;
$function$;

revoke all on function public.decide_admin_request(uuid, text, text, jsonb) from public, anon;
grant execute on function public.decide_admin_request(uuid, text, text, jsonb) to authenticated;
