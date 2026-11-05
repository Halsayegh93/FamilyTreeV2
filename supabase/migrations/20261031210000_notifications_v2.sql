-- نظام الإشعارات الجديد (طلب المالك ٢٠٢٦-١٠-٣١):
--  ١) كل تغيير في بيانات عضو (الشجرة العامة + شجرة النساء) يُسجَّل من السيرفر نفسه بالقيمة قبل وبعد،
--     ويصل للإدارة إشعار واحد واضح، وللعضو إشعار «عدّلت الإدارة بياناتك» إن عدّلها إداري.
--  ٢) كل إشعار يحمل details.sender: الإدارة / عضو / النظام — الأعضاء يرون «الإدارة»، والإداريون يرون معها الاسم.
--  ٣) إشعارات التعديل القديمة التي ترسلها التطبيقات نفسها تُسقَط (السيرفر صار المصدر) حتى لا تتكرر.
-- التطبيقات القديمة تعرض title/body كما هي، فكلها نصوص عربية مقروءة.

-- اسم مختصر: الاسم الأول + اسم الأب
create or replace function public.notif_short_name(p_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select nullif(btrim(array_to_string((regexp_split_to_array(btrim(coalesce(nullif(p.full_name, ''), p.first_name)), '\s+'))[1:2], ' ')), '')
       from public.profiles p where p.id = p_id),
    (select nullif(btrim(array_to_string((regexp_split_to_array(btrim(coalesce(nullif(w.full_name, ''), w.first_name)), '\s+'))[1:2], ' ')), '')
       from public.women_members w where w.id = p_id));
$$;

create or replace function public.notif_is_admin(p_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.profiles p
                 where p.id = p_id and p.role in ('owner','admin','monitor','supervisor'));
$$;

-- قيمة الحقل كما يقرؤها الإنسان
create or replace function public.notif_fmt(p_field text, p_val jsonb)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v text := p_val #>> '{}';
begin
  if p_val is null or p_val = 'null'::jsonb or btrim(coalesce(v, '')) = '' then
    return 'غير مسجّل';
  end if;
  if jsonb_typeof(p_val) = 'boolean' then
    return case when p_field in ('is_deceased') then case when v = 'true' then 'متوفى' else 'على قيد الحياة' end
                when p_field = 'is_married' then case when v = 'true' then 'متزوج' else 'غير متزوج' end
                when p_field = 'is_hidden_from_tree' then case when v = 'true' then 'مخفي' else 'ظاهر' end
                else case when v = 'true' then 'نعم' else 'لا' end end;
  end if;
  if p_field in ('father_id','mother_id','husband_id','parent_id') then
    return coalesce(public.notif_short_name(v::uuid), 'عضو');
  end if;
  if p_field = 'gender' then
    return case lower(v) when 'male' then 'ذكر' when 'female' then 'أنثى' else v end;
  end if;
  if p_field = 'role' then
    return case v when 'owner' then 'المالك' when 'admin' then 'مدير' when 'monitor' then 'مراقب'
                  when 'supervisor' then 'مشرف' when 'member' then 'عضو' when 'pending' then 'بانتظار الموافقة' else v end;
  end if;
  if p_field = 'status' then
    return case v when 'active' then 'مفعّل' when 'frozen' then 'مجمّد' when 'pending' then 'بانتظار الموافقة' else v end;
  end if;
  if p_field = 'phone_number' then
    return '••••' || right(regexp_replace(v, '\D', '', 'g'), 4);
  end if;
  if p_field in ('avatar_url','photo_url') then
    return 'صورة';
  end if;
  return left(v, 120);
end;
$$;

-- الحقول المتابَعة وأسماؤها
create or replace function public.notif_field_label(p_field text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_field
    when 'first_name' then 'الاسم'
    when 'family_name' then 'العائلة'
    when 'phone_number' then 'رقم الجوال'
    when 'birth_date' then 'تاريخ الميلاد'
    when 'death_date' then 'تاريخ الوفاة'
    when 'is_deceased' then 'الوفاة'
    when 'father_id' then 'الأب'
    when 'parent_id' then 'الأب'
    when 'mother_id' then 'الأم'
    when 'husband_id' then 'الزوج'
    when 'gender' then 'الجنس'
    when 'is_married' then 'الحالة الاجتماعية'
    when 'avatar_url' then 'الصورة الشخصية'
    when 'photo_url' then 'الصورة الشخصية'
    when 'role' then 'الصلاحية'
    when 'status' then 'حالة الحساب'
    when 'is_hidden_from_tree' then 'الظهور في الشجرة'
    when 'bio' then 'النبذة'
  end;
$$;

-- قلب النظام: يسجّل التغيير ويُخطر
create or replace function public.notify_member_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  v_new jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  v_row jsonb := coalesce(v_new, v_old);
  v_subject uuid := (v_row ->> 'id')::uuid;
  v_actor uuid := public.current_profile_id();
  v_actor_admin boolean;
  v_women boolean := tg_table_name = 'women_members';
  v_fields text[];
  f text;
  v_changes jsonb := '[]'::jsonb;
  v_labels text := '';
  v_who text;
  v_actor_name text;
  v_title text;
  v_body text;
  v_action text;
  v_details jsonb;
  admin_id uuid;
begin
  -- التغييرات المتسلسلة (نسخ الشجرتين، تحديث أسماء الأبناء) ليست فعلاً جديداً
  if pg_trigger_depth() > 1 then return null; end if;
  -- صيانة السيرفر بلا مستخدم: لا إشعار
  if v_actor is null then return null; end if;
  -- شجرة النساء: الإناث فقط (الذكور نسخة من الشجرة العامة)
  if v_women and coalesce(lower(v_row ->> 'gender'), 'female') <> 'female' then return null; end if;
  -- تسجيل جديد بانتظار الموافقة له إشعاره الخاص (طلب الانضمام)
  if not v_women and tg_op = 'INSERT' and coalesce(v_row ->> 'role', '') = 'pending' then return null; end if;

  v_fields := case when v_women
    then array['first_name','birth_date','death_date','is_deceased','is_married','parent_id','mother_id','husband_id','avatar_url','is_hidden_from_tree']
    else array['first_name','family_name','phone_number','birth_date','death_date','is_deceased','father_id','mother_id','gender','is_married','avatar_url','role','status','is_hidden_from_tree','bio'] end;

  if tg_op = 'UPDATE' then
    foreach f in array v_fields loop
      if (v_old -> f) is distinct from (v_new -> f) then
        v_changes := v_changes || jsonb_build_array(jsonb_build_object(
          'field', f, 'label', public.notif_field_label(f),
          'before', public.notif_fmt(f, v_old -> f), 'after', public.notif_fmt(f, v_new -> f),
          'kind', case when f in ('avatar_url') then 'image' else 'text' end,
          'before_url', case when f = 'avatar_url' then v_old ->> f end,
          'after_url', case when f = 'avatar_url' then v_new ->> f end));
        v_labels := v_labels || public.notif_field_label(f) || '، ';
      end if;
    end loop;
    if jsonb_array_length(v_changes) = 0 then return null; end if;
    v_labels := rtrim(v_labels, '، ');
    v_action := 'edit';
  elsif tg_op = 'INSERT' then
    v_action := 'add';
  else
    v_action := 'delete';
  end if;

  v_who := coalesce(nullif(btrim(array_to_string((regexp_split_to_array(btrim(coalesce(nullif(v_row ->> 'full_name', ''), v_row ->> 'first_name', '')), '\s+'))[1:3], ' ')), ''), 'عضو');
  v_actor_name := coalesce(public.notif_short_name(v_actor), 'عضو');
  v_actor_admin := public.notif_is_admin(v_actor);

  v_title := case v_action
    when 'edit' then case when v_actor = v_subject then v_actor_name || ' عدّل بياناته' else 'تعديل بيانات ' || v_who end
    when 'add' then case when v_women then 'إضافة في شجرة النساء: ' || v_who else 'إضافة عضو: ' || v_who end
    else case when v_women then 'حذف من شجرة النساء: ' || v_who else 'حذف عضو: ' || v_who end end;
  v_body := case v_action
    when 'edit' then 'تغيّر: ' || v_labels
    when 'add' then coalesce('الأب: ' || public.notif_short_name(coalesce(v_row ->> 'father_id', v_row ->> 'parent_id')::uuid),
                             'الزوج: ' || public.notif_short_name((v_row ->> 'husband_id')::uuid), v_who)
    else v_who end;

  v_details := jsonb_build_object('v', 2, 'action', v_action,
    'tree', case when v_women then 'women' else 'main' end,
    'subject', jsonb_build_object('id', v_subject, 'name', v_who),
    'actor', jsonb_build_object('id', v_actor, 'name', v_actor_name, 'is_admin', v_actor_admin),
    'changes', v_changes);

  -- الإدارة: كل إداري مفعّل عدا من قام بالتغيير
  for admin_id in
    select p.id from public.profiles p
     where p.role in ('owner','admin','monitor','supervisor') and p.status = 'active' and p.id <> v_actor
  loop
    insert into public.notifications (target_member_id, title, body, kind, created_by, is_read, details, subject_member_id)
    values (admin_id, v_title, v_body, 'member_change', v_actor, false, v_details, case when v_women then null else v_subject end);
  end loop;

  -- العضو نفسه: إداري عدّل بياناته
  if not v_women and v_action = 'edit' and v_actor_admin and v_actor <> v_subject
     and coalesce(v_row ->> 'role', '') not in ('pending') then
    insert into public.notifications (target_member_id, title, body, kind, created_by, is_read, details, subject_member_id)
    values (v_subject, 'عدّلت الإدارة بياناتك', 'تغيّر: ' || v_labels, 'my_profile_change', v_actor, false,
            v_details - 'actor', v_subject);
  end if;

  return null;
end;
$$;

drop trigger if exists trg_zz_notify_member_change on public.profiles;
create trigger trg_zz_notify_member_change
  after insert or update or delete on public.profiles
  for each row execute function public.notify_member_change();

drop trigger if exists trg_zz_notify_member_change on public.women_members;
create trigger trg_zz_notify_member_change
  after insert or update or delete on public.women_members
  for each row execute function public.notify_member_change();

-- إشعارات شجرة النساء القديمة: صارت من notify_member_change
create or replace function public.log_women_change_to_activity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- استُبدل بـ notify_member_change (٢٠٢٦-١٠-٣١) — يبقى المُطلِق بلا عمل
  return coalesce(new, old);
end;
$$;

-- المرسل على كل إشعار: الإدارة / عضو / النظام (الاسم للإداريين فقط)
create or replace function public.notification_stamp_sender()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_target_admin boolean := public.notif_is_admin(new.target_member_id);
  v_sender jsonb;
begin
  if new.details ? 'sender' then return new; end if;
  if new.created_by is null then
    v_sender := jsonb_build_object('type', 'admin');
  elsif public.notif_is_admin(new.created_by) then
    v_sender := jsonb_build_object('type', 'admin',
      'name', case when v_target_admin then public.notif_short_name(new.created_by) end);
  else
    v_sender := jsonb_build_object('type', 'member', 'id', new.created_by,
      'name', public.notif_short_name(new.created_by));
  end if;
  new.details := coalesce(new.details, '{}'::jsonb) || jsonb_build_object('sender', v_sender);
  return new;
end;
$$;

drop trigger if exists trg_zz_notification_sender on public.notifications;
create trigger trg_zz_notification_sender
  before insert on public.notifications
  for each row execute function public.notification_stamp_sender();

-- إشعارات التعديل التي ترسلها التطبيقات نفسها: السيرفر صار المصدر — تُسقط بهدوء
create or replace function public.drop_legacy_client_change_notifications()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(auth.role(), '') = 'authenticated' and pg_trigger_depth() = 1
     and (new.kind like 'admin_edit%' or new.kind in ('profile_update','member_delete','member_add')) then
    return null;
  end if;
  return new;
end;
$$;

drop trigger if exists aa1_drop_legacy_client_change on public.notifications;
create trigger aa1_drop_legacy_client_change
  before insert on public.notifications
  for each row execute function public.drop_legacy_client_change_notifications();
