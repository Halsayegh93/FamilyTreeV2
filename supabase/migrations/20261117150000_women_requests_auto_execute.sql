-- طلبات شجرة النساء تُنفَّذ تلقائياً عند القبول (طلب المالك ٢٠٢٦-١١-١٧ «التنفيذ التلقائي»)
--
-- كانت طلبات شجرة النساء tree_edit/add بلا اسم جديد: القبول يغلق الطلب ولا يكتب شيئاً، فقُبلت أربع
-- بنات لمحمد يوسف ولم يُضفن. الآن يحمل الطلب حقلاً منظّماً `women` في details:
--   {"kind": "child"|"sister"|"edit_name"|"edit_birth"|"deceased"|"delete"|"set_mother",
--    "motherId": "<set_mother: الأم من زوجات أب العقدة>",
--    "nodeId": "<عقدة شجرة النساء: الأب/الأم للإضافة، أو المستهدفة للتعديل>",
--    "name": "<الاسم الأول>", "gender": "female"|"male", "birth": "YYYY-MM-DD", "deceased": true, "death": "YYYY-MM-DD"}
-- والقبول من `decide_admin_request` ينفّذه في المعاملة نفسها. الطلب بلا `women` يبقى كما كان (يدوي).
-- العقدة الذكر التي لها ملف في `profiles` (نسخة من الشجرة العامة) تُعدَّل في `profiles` (المزامنة تنقلها)،
-- وغيرها في `women_members`. الإضافة المكرّرة (نفس الاسم تحت نفس الأب والأم) لا تُضاف مرة ثانية — فقبول طلب
-- نفّذته الإدارة يدوياً قبل القبول لا يكرّر السجل.

create or replace function private.apply_women_request(p_w jsonb, p_role text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  uuid_re  constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  kind     text := p_w->>'kind';
  node_id  uuid;
  node     public.women_members%rowtype;
  in_prof  boolean;
  nm       text := btrim(regexp_replace(coalesce(p_w->>'name', ''), '\s+', ' ', 'g'));
  fem      boolean := coalesce(p_w->>'gender', 'female') = 'female';
  v_birth  date;
  v_death  date;
  dead     boolean := coalesce((p_w->>'deceased')::boolean, false);
  par      uuid;
  mom      uuid;
  par_full text;
  new_id   uuid;
  was_dead boolean;
  body     text;
  death    jsonb;
begin
  if kind is null or kind not in ('child', 'sister', 'edit_name', 'edit_birth', 'deceased', 'delete', 'set_mother')
     or coalesce(p_w->>'nodeId', '') !~ uuid_re
     or coalesce(p_w->>'gender', 'female') not in ('female', 'male')
     or coalesce(jsonb_typeof(p_w->'deceased'), 'boolean') <> 'boolean' then
    raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload', detail = 'women';
  end if;
  begin
    v_birth := nullif(btrim(coalesce(p_w->>'birth', '')), '')::date;
    v_death := nullif(btrim(coalesce(p_w->>'death', '')), '')::date;
  exception when others then
    raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload', detail = 'women.date';
  end;
  node_id := (p_w->>'nodeId')::uuid;
  select * into node from public.women_members where id = node_id for update;
  if not found then
    raise exception 'women_node_not_found' using errcode = 'P0002', hint = 'women_node_not_found';
  end if;
  in_prof := exists (select 1 from public.profiles p where p.id = node_id);

  -- ═══ إضافة ابن/ابنة أو أخت ═══
  if kind in ('child', 'sister') then
    if nm = '' then
      raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload', detail = 'women.name';
    end if;
    if kind = 'sister' then fem := true; end if;
    if lower(coalesce(node.gender, '')) = 'female' then
      -- أبناء المرأة تحت زوجها، وهي أمّهم
      if node.husband_id is null then
        raise exception 'women_needs_husband' using errcode = 'P0001', hint = 'women_needs_husband';
      end if;
      par := node.husband_id;
      mom := node.id;
      -- ابن ذكر لزوج من العائلة يُضاف في الشجرة العامة لا هنا
      if not fem and exists (select 1 from public.profiles p where p.id = par) then
        raise exception 'women_son_in_main_tree' using errcode = 'P0001', hint = 'women_son_in_main_tree';
      end if;
    else
      -- رجل: البنت تحته هنا، والابن الذكر في الشجرة العامة
      if not fem then
        raise exception 'women_son_in_main_tree' using errcode = 'P0001', hint = 'women_son_in_main_tree';
      end if;
      par := node.id;
      mom := null;
    end if;
    select coalesce(nullif(btrim(w.full_name), ''), w.first_name) into par_full from public.women_members w where w.id = par;
    if par_full is null then
      select p.full_name into par_full from public.profiles p where p.id = par;
    end if;
    -- مكرّر؟ (أُضيف يدوياً قبل القبول) — لا يُضاف مرة ثانية
    select w.id into new_id from public.women_members w
     where w.parent_id = par and w.mother_id is not distinct from mom
       and btrim(w.first_name) = split_part(nm, ' ', 1)
     limit 1;
    if new_id is not null then
      return jsonb_build_object('body', 'موجود في الشجرة: «' || nm || '»', 'id', new_id);
    end if;
    insert into public.women_members (first_name, full_name, parent_id, mother_id, gender, birth_date,
                                      is_deceased, death_date, sort_order)
    values (split_part(nm, ' ', 1), btrim(split_part(nm, ' ', 1) || ' ' || coalesce(par_full, '')), par, mom,
            case when fem then 'female' else 'male' end, v_birth, dead, case when dead then v_death end,
            coalesce((select max(c.sort_order) + 1 from public.women_members c where c.parent_id = par), 0))
    returning id into new_id;
    body := 'تمت إضافة «' || split_part(nm, ' ', 1) || '» تحت «' || coalesce(par_full, '') || '»';
    return jsonb_build_object('body', body, 'id', new_id);
  end if;

  -- ═══ تعديل الاسم ═══
  if kind = 'edit_name' then
    if nm = '' then
      raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload', detail = 'women.name';
    end if;
    if in_prof then
      update public.profiles
         set first_name = split_part(nm, ' ', 1),
             full_name = btrim(split_part(nm, ' ', 1) || ' ' || regexp_replace(coalesce(full_name, ''), '^\S+\s*', ''))
       where id = node_id;
    else
      update public.women_members
         set first_name = split_part(nm, ' ', 1),
             full_name = btrim(split_part(nm, ' ', 1) || ' ' || regexp_replace(coalesce(full_name, ''), '^\S+\s*', ''))
       where id = node_id;
      -- حسابها المربوط يأخذ الاسم نفسه
      if node.linked_user_id is not null then
        update public.profiles p set first_name = w.first_name, full_name = w.full_name
          from public.women_members w where w.id = node_id and p.id = node.linked_user_id;
      end if;
    end if;
    return jsonb_build_object('body', 'تم تغيير الاسم إلى «' || split_part(nm, ' ', 1) || '»');
  end if;

  -- ═══ تعديل الميلاد ═══
  if kind = 'edit_birth' then
    if v_birth is null then
      raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload', detail = 'women.birth';
    end if;
    if in_prof then
      update public.profiles set birth_date = v_birth where id = node_id;
    else
      update public.women_members set birth_date = v_birth where id = node_id;
    end if;
    return jsonb_build_object('body', 'تم تحديث تاريخ الميلاد إلى «' || v_birth::text || '»');
  end if;

  -- ═══ تسجيل وفاة ═══
  if kind = 'deceased' then
    if in_prof then
      select coalesce(p.is_deceased, false) into was_dead from public.profiles p where p.id = node_id;
      update public.profiles set is_deceased = true, death_date = coalesce(v_death, death_date) where id = node_id;
    else
      was_dead := coalesce(node.is_deceased, false);
      update public.women_members set is_deceased = true, death_date = coalesce(v_death, death_date) where id = node_id;
    end if;
    if not was_dead then
      death := jsonb_build_object('member_id', node_id, 'name', coalesce(nullif(node.full_name, ''), node.first_name),
                                  'is_female', lower(coalesce(node.gender, '')) = 'female',
                                  'death_date', case when v_death is null then null else to_jsonb(v_death::text) end);
    end if;
    return jsonb_build_object('body', 'تم تسجيل وفاة «' || coalesce(node.first_name, '') || '»', 'death', death);
  end if;

  -- ═══ اختيار الأم من زوجات الأب ═══
  if kind = 'set_mother' then
    if coalesce(p_w->>'motherId', '') !~ uuid_re then
      raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload', detail = 'women.motherId';
    end if;
    if node.parent_id is null or not exists (
         select 1 from public.women_members w
          where w.id = (p_w->>'motherId')::uuid and w.husband_id = node.parent_id
            and lower(coalesce(w.gender, '')) = 'female') then
      raise exception 'women_mother_not_wife' using errcode = 'P0001', hint = 'women_mother_not_wife';
    end if;
    update public.women_members set mother_id = (p_w->>'motherId')::uuid where id = node_id;
    return jsonb_build_object('body', 'تم تحديد الأم لـ «' || coalesce(node.first_name, '') || '»');
  end if;

  -- ═══ حذف ═══ (حذف عقدة شجرة النساء للمالك والمدير — مثل سياسة women_members_delete)
  if kind = 'delete' then
    if p_role not in ('owner', 'admin') then
      raise exception 'not_allowed' using errcode = '42501', hint = 'not_allowed';
    end if;
    if in_prof then
      raise exception 'women_delete_in_main_tree' using errcode = 'P0001', hint = 'women_delete_in_main_tree';
    end if;
    if node.linked_user_id is not null then
      raise exception 'women_has_account' using errcode = 'P0001', hint = 'women_has_account';
    end if;
    -- حماية روابط العائلة ترفض حذف من لها أبناء/زوج مرتبطون (family_links_protected)
    delete from public.women_members where id = node_id;
    return jsonb_build_object('body', 'تم حذف «' || coalesce(node.first_name, '') || '» من شجرة النساء');
  end if;

  raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload', detail = 'women.kind';
end;
$$;

revoke all on function private.apply_women_request(jsonb, text) from public, anon, authenticated;

-- ربطها في القبول: طلب tree_edit فيه `women` يُنفَّذ بها بدل فروع الإجراء
do $mig$
declare
  src text := pg_get_functiondef('private.decide_admin_request_core(uuid,text,text,jsonb)'::regprocedure);
  anchor_a text := $a$    if approving then
      n_body := 'تم قبول طلب تعديل الشجرة';
      if act = 'edit_name' then$a$;
  patch_a text := $a$    if approving then
      n_body := 'تم قبول طلب تعديل الشجرة';
      -- طلب شجرة النساء المنظّم (٢٠٢٦-١١-١٧): التنفيذ التلقائي
      if d is not null and jsonb_typeof(d->'women') = 'object' then
        v_json := private.apply_women_request(d->'women', my_role);
        n_body := coalesce(v_json->>'body', n_body);
        if jsonb_typeof(v_json->'death') = 'object' then death := v_json->'death'; end if;
      elsif act = 'edit_name' then$a$;
begin
  if position(anchor_a in src) = 0 then
    raise exception 'decide_admin_request_core anchor not found — function changed, update this migration';
  end if;
  if position('apply_women_request' in src) > 0 then
    return;  -- مطبَّق
  end if;
  execute replace(src, anchor_a, patch_a);
end
$mig$;
