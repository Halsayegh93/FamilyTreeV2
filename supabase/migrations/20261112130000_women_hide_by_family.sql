-- «إخفاء الإناث من شجرة النساء من تعديل الملف الشخصي» (طلب المالك ٢٠٢٦-١١-١٢، اختياره: ٢ «أ» الزوجة والبنات،
-- ٣ «أ» الإدارة تشوف ولا ترجّعها — القرار لأهلها).
--
-- ١) من أخفاها ومتى: `hidden_by` · `hidden_at` · `hidden_by_family` يختمها `trg_women_hidden_stamp` عند تغيّر الإخفاء.
--    ما أخفاه الأهل (عبر الدالتين الذاتيتين أدناه) لا يُظهره غيرهم: إظهاره من غير مسارهم يُرفض (`hint = family_hidden`)
--    — حتى من الإدارة؛ صيانة SQL بلا مستخدم تمرّ.
-- ٢) `set_self_woman_hidden(p_woman_id, p_hidden)`: زوجته أو ابنته في شجرة النساء فقط (عقدته `my_active_women_node()`).
--    `set_self_wife_hidden` القديمة (نسخ سابقة) تعلّم «أخفاها الأهل» أيضاً.
-- ٣) الإدارة (المالك · المدير · المراقب) ترى المخفيات في شجرة النساء — بعلامة في التطبيق؛ الأعضاء لا يرونها كما كان.
-- ٤) إشعار الإدارة جملة واضحة: «أخفى فلان ابنته فلانة من شجرة النساء» بدل «تعديل بيانات… تغيّر: …».
-- التراجع: supabase/rollback/20261112130000_women_hide_by_family_rollback.sql

-- ١) الأعمدة والختم
alter table public.women_members
  add column if not exists hidden_by uuid,
  add column if not exists hidden_at timestamptz,
  add column if not exists hidden_by_family boolean not null default false;

create or replace function public.women_hidden_stamp()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := public.current_profile_id();
  v_family boolean := coalesce(current_setting('family.self_hide', true), '') = 'on';
begin
  if new.is_hidden_from_tree is not distinct from old.is_hidden_from_tree then
    return new;
  end if;
  if coalesce(new.is_hidden_from_tree, false) then
    new.hidden_by := v_actor;
    new.hidden_at := now();
    new.hidden_by_family := v_family;
  else
    -- أخفاها أهلها: الإظهار منهم وحدهم (اختيار المالك «الإدارة تشوف بس»)
    if old.hidden_by_family and not v_family and v_actor is not null then
      raise exception 'أخفاها أهلها — إظهارها منهم من «تعديل الملف الشخصي»'
        using errcode = '42501', hint = 'family_hidden';
    end if;
    new.hidden_by := null;
    new.hidden_at := null;
    new.hidden_by_family := false;
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_women_hidden_stamp on public.women_members;
create trigger trg_women_hidden_stamp
  before update of is_hidden_from_tree on public.women_members
  for each row execute function public.women_hidden_stamp();

-- ٢) الدالة الذاتية: زوجته أو ابنته
create or replace function public.set_self_woman_hidden(p_woman_id uuid, p_hidden boolean)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  me uuid := public.my_active_women_node();
begin
  if me is null then
    raise exception 'no_node' using errcode = '42501', hint = 'no_node';
  end if;
  if not exists (
    select 1 from public.women_members w
     where w.id = p_woman_id
       and coalesce(lower(w.gender), 'female') = 'female'
       and (w.husband_id = me or w.parent_id = me)
  ) then
    raise exception 'ليست زوجتك أو ابنتك في شجرة النساء' using errcode = '42501', hint = 'not_your_family';
  end if;
  perform set_config('family.self_hide', 'on', true);
  update public.women_members
     set is_hidden_from_tree = coalesce(p_hidden, false)
   where id = p_woman_id;
  perform set_config('family.self_hide', 'off', true);
end;
$function$;

revoke all on function public.set_self_woman_hidden(uuid, boolean) from public, anon;
grant execute on function public.set_self_woman_hidden(uuid, boolean) to authenticated;

create or replace function public.set_self_wife_hidden(p_wife_id uuid, p_hidden boolean)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare me uuid := public.my_active_women_node();
begin
  if me is null then raise exception 'no_node'; end if;
  if not exists (
    select 1 from public.women_members where id = p_wife_id and husband_id = me
  ) then raise exception 'not_your_wife'; end if;
  perform set_config('family.self_hide', 'on', true);
  update public.women_members
     set is_hidden_from_tree = coalesce(p_hidden, false)
   where id = p_wife_id;
  perform set_config('family.self_hide', 'off', true);
end; $function$;

-- ٣) الإدارة ترى المخفيات (المالك · المدير · المراقب)
drop policy if exists women_members_select on public.women_members;
create policy women_members_select on public.women_members
  for select to authenticated
  using (
    ((is_hidden_from_tree = false)
      or (id = (select public.my_women_node()))
      or (husband_id = (select public.my_women_node()))
      or (parent_id = (select public.my_women_node()))
      or (mother_id = (select public.my_women_node()))
      or ((select public.current_user_role()) = any (array['owner', 'admin', 'monitor'])))
    and ((select public.is_approved_member()) or (id = (select public.my_women_node())))
  );

-- ٤) إشعار واضح للإخفاء والإظهار (بقية الدالة كما هي حرفياً)
CREATE OR REPLACE FUNCTION public.notify_member_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  v_rel text;
  admin_id uuid;
begin
  if pg_trigger_depth() > 1 then return null; end if;
  -- ربط طلب انضمام: نقل سجل، لا «حذف عضو» ولا «تعديل بيانات»
  if current_setting('family.merging', true) = 'on' then return null; end if;
  if v_actor is null then return null; end if;
  if v_women and coalesce(lower(v_row ->> 'gender'), 'female') <> 'female' then return null; end if;
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

  -- العضو أضاف ابنه بنفسه: «تمت إضافة ابن»، و«راجعه» إن تطابق الاسم الكامل مع غيره أو الميلاد مع أخ
  if not v_women and v_action = 'add' and current_setting('family.self_child', true) = 'on' then
    v_title := 'تمت إضافة ابن';
    v_body := v_actor_name || ' أضاف ابنه ' || coalesce(v_row ->> 'first_name', v_who);
    v_details := v_details || jsonb_build_object('self_child', true, 'review', exists (
      select 1 from public.profiles p where p.id <> v_subject and (
        public.child_name_key(p.full_name) = public.child_name_key(v_row ->> 'full_name')
        or (p.father_id = v_actor and p.birth_date is not null and p.birth_date = (v_row ->> 'birth_date')::date))));
  end if;

  -- الإخفاء أو الإظهار في شجرة النساء وحده (طلب المالك ٢٠٢٦-١١-١٢): «أخفى فلان ابنته فلانة من شجرة النساء.»
  if v_women and v_action = 'edit' and jsonb_array_length(v_changes) = 1
     and v_changes -> 0 ->> 'field' = 'is_hidden_from_tree' then
    v_rel := case when (v_row ->> 'husband_id')::uuid = v_actor then 'زوجته '
                  when (v_row ->> 'parent_id')::uuid = v_actor then 'ابنته '
                  else '' end;
    if coalesce((v_new ->> 'is_hidden_from_tree')::boolean, false) then
      v_title := 'إخفاء من شجرة النساء';
      v_body := 'أخفى ' || v_actor_name || ' ' || v_rel || v_who || ' من شجرة النساء.';
    else
      v_title := 'إظهار في شجرة النساء';
      v_body := 'أظهر ' || v_actor_name || ' ' || v_rel || v_who || ' في شجرة النساء.';
    end if;
    v_details := v_details || jsonb_build_object('women_visibility',
      case when coalesce((v_new ->> 'is_hidden_from_tree')::boolean, false) then 'hidden' else 'shown' end);
  end if;

  for admin_id in
    select p.id from public.profiles p
     where p.role in ('owner','admin','monitor','supervisor') and p.status = 'active' and p.id <> v_actor
  loop
    insert into public.notifications (target_member_id, title, body, kind, created_by, is_read, details, subject_member_id)
    values (admin_id, v_title, v_body, 'admin_edit', v_actor, false, v_details, case when v_women or tg_op = 'DELETE' then null else v_subject end);
  end loop;

  if not v_women and v_action = 'edit' and v_actor_admin and v_actor <> v_subject
     and coalesce(v_row ->> 'role', '') not in ('pending') then
    insert into public.notifications (target_member_id, title, body, kind, created_by, is_read, details, subject_member_id)
    values (v_subject, 'عدّلت الإدارة بياناتك', 'تغيّر: ' || v_labels, 'my_profile_change', v_actor, false,
            v_details - 'actor', v_subject);
  end if;

  return null;
end;
$function$;
