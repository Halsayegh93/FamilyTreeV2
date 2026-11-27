-- تراجع 20261127150000_daughter_daughters — يعيد الحي كما كان قبله حرفياً في الدوال المعدّلة.
-- عُقد «بنت بنت» والأزواج التي أُنشئت بعده تبقى (لا فكّ لأي رابط)؛ طلبات lineage_request بنوع daughter_daughter المعلّقة
-- تبقى ولا يقبلها decide_lineage_request القديم (يطلب صفّ daughter_son_lineage) — ارفضها قبل التراجع إن وُجدت.

-- المزامنة كما كانت (20260710130000)
create or replace function public.sync_profile_update_to_women()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  -- يتأهّل كابن ذكر له أب → تأكّد من وجود/تحديث المرآة (كما كان).
  if new.father_id is not null
     and (new.gender is null or lower(new.gender) = 'male') then
    insert into public.women_members (
      id, first_name, full_name, parent_id, gender,
      is_deceased, birth_date, death_date, is_hidden_from_tree,
      sort_order, photo_url, avatar_url
    ) values (
      new.id,
      coalesce(new.first_name, ''),
      coalesce(nullif(new.full_name, ''), new.first_name, ''),
      new.father_id,
      'male',
      coalesce(new.is_deceased, false),
      new.birth_date, new.death_date,
      coalesce(new.is_hidden_from_tree, false),
      coalesce(new.sort_order, 0),
      new.photo_url, new.avatar_url
    )
    on conflict (id) do update set
      first_name          = excluded.first_name,
      full_name           = excluded.full_name,
      parent_id           = excluded.parent_id,
      is_deceased         = excluded.is_deceased,
      birth_date          = excluded.birth_date,
      death_date          = excluded.death_date,
      is_hidden_from_tree = excluded.is_hidden_from_tree;
  else
    -- لم يعد ابناً ذكراً له أب (مثلاً أُزيل الأب، أو هو جذر فرع father_id NULL).
    -- ⚠️ لا تحذف العقدة إذا لها تابعون في شجرة النساء — الحذف يفصلهم نهائياً.
    if exists (
      select 1 from public.women_members w
      where w.husband_id = new.id
         or w.parent_id  = new.id
         or w.mother_id  = new.id
    ) then
      -- أبقِ العقدة (لحماية الزوجة/البنات/الأم) وحدّث حقولها فقط.
      update public.women_members set
        first_name          = coalesce(new.first_name, ''),
        full_name           = coalesce(nullif(new.full_name, ''), new.first_name, ''),
        is_deceased         = coalesce(new.is_deceased, false),
        birth_date          = new.birth_date,
        death_date          = new.death_date,
        is_hidden_from_tree = coalesce(new.is_hidden_from_tree, false)
      where id = new.id;
    else
      -- مرآة يتيمة بلا تابعين → حذفها آمن.
      delete from public.women_members where id = new.id;
    end if;
  end if;
  return new;
end;
$function$;

-- قرار الإدارة كما كان (20261108090000)
create or replace function public.decide_lineage_request(p_request_id uuid, p_decision text, p_reason text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  uid      uuid := auth.uid();
  me       uuid := public.current_profile_id();
  my_role  text := coalesce(public.current_user_role(), 'pending');
  decision text := lower(btrim(coalesce(p_decision, '')));
  reason   text := nullif(btrim(coalesce(p_reason, '')), '');
  r        public.admin_requests%rowtype;
  d        jsonb;
  nmj      jsonb;
  l        public.daughter_son_lineage%rowtype;
  son      public.profiles%rowtype;
  gf       public.profiles%rowtype;
  gnode    public.women_members%rowtype;
  mom      public.women_members%rowtype;
  gfid     uuid;
  mfirst   text;
  hid      uuid;
  hname    text;
  son_id   uuid;
  son_first text;
  new_mom  boolean := false;
begin
  if my_role not in ('owner', 'admin', 'monitor') then
    raise exception 'طلبات النسب للمالك والمدير والمراقب' using errcode = '42501', hint = 'not_allowed';
  end if;
  if decision not in ('approve', 'reject') then
    raise exception 'bad_decision' using errcode = '22023', hint = 'bad_decision';
  end if;
  select * into r from public.admin_requests where id = p_request_id for update;
  if not found or r.request_type is distinct from 'lineage_request' then
    raise exception 'الطلب غير موجود' using errcode = 'P0001', hint = 'request_not_found';
  end if;
  if r.status is distinct from 'pending' then
    raise exception 'الطلب عولج من قبل' using errcode = 'P0001', hint = 'already_handled';
  end if;
  if my_role <> 'owner' and (r.requester_id = any (array[uid, me]) or r.member_id = any (array[uid, me])) then
    raise exception 'لا تقرّر في طلبك' using errcode = '42501', hint = 'own_request';
  end if;

  if decision = 'reject' then
    update public.admin_requests
       set status = 'rejected', admin_reply = reason, replied_by = me, replied_at = now()
     where id = r.id;
    insert into public.notifications (target_member_id, title, body, kind, created_by)
    values (r.requester_id,
            private.daughter_sons_text('notify_rejected_title', 'راجع بياناتك وأرسلها من جديد'),
            private.daughter_sons_text('notify_rejected_body', 'افتح «أكمل حسابك» وراجع اختيار أمّك وأبوك')
              || coalesce(E'\nالسبب: ' || reason, ''), 'request_rejected', me);
    return jsonb_build_object('ok', true, 'request_id', r.id, 'status', 'rejected');
  end if;

  begin
    d := r.details::jsonb;
  exception when others then
    d := null;
  end;
  if d is null or jsonb_typeof(d) <> 'object' then
    raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload';
  end if;
  nmj := d->'new_mother';
  new_mom := nmj is not null and jsonb_typeof(nmj) = 'object';
  if not new_mom and coalesce(d->>'mother_id', '') = '' then
    raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload';
  end if;

  select * into l from public.daughter_son_lineage where profile_id = r.requester_id for update;
  if not found or l.completed_at is not null then
    raise exception 'نسب العضو مكتمل' using errcode = 'P0001', hint = 'not_needed';
  end if;
  select * into son from public.profiles where id = r.requester_id;
  if not found then
    raise exception 'صاحب الطلب لم يعد له حساب' using errcode = 'P0001', hint = 'requester_gone';
  end if;
  if exists (select 1 from public.women_members w where w.linked_user_id = son.id) then
    raise exception 'الحساب مربوط بشجرة النساء من قبل' using errcode = 'P0001', hint = 'already_linked';
  end if;

  if new_mom then
    -- «أم جديدة»: بنت لعقدة أبيها في شجرة النساء (نسخة رجل الشجرة بنفس المعرّف — تُنشأ إن غابت)
    begin
      gfid := (nmj->>'father_id')::uuid;
    exception when others then
      gfid := null;
    end;
    mfirst := btrim(coalesce(nmj->>'first_name', ''));
    select * into gf from public.profiles where id = gfid and lower(coalesce(gender, 'male')) <> 'female';
    if not found or mfirst = '' or coalesce(d->>'father_id', '') <> '' then
      raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload';
    end if;
    select * into gnode from public.women_members where id = gf.id for update;
    if not found then
      insert into public.women_members (id, first_name, full_name, parent_id, gender, is_deceased, sort_order)
      values (gf.id, gf.first_name, coalesce(nullif(btrim(gf.full_name), ''), gf.first_name),
              (select w.id from public.women_members w where w.id = gf.father_id), 'male',
              coalesce(gf.is_deceased, false), coalesce(gf.sort_order, 0))
      returning * into gnode;
    elsif lower(coalesce(gnode.gender, 'male')) <> 'male' then
      raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload';
    end if;
    insert into public.women_members (id, first_name, full_name, parent_id, gender, is_deceased, is_married, sort_order)
    values (gen_random_uuid(), mfirst,
            btrim(mfirst || ' ' || coalesce(nullif(btrim(gnode.full_name), ''), btrim(coalesce(gnode.first_name, '')))),
            gnode.id, 'female', coalesce((nmj->>'is_deceased')::boolean, false), true,
            coalesce((select max(c.sort_order) + 1 from public.women_members c where c.parent_id = gnode.id), 0))
    returning * into mom;
  else
    select * into mom from public.women_members where id = (d->>'mother_id')::uuid for update;
    if not found or lower(coalesce(mom.gender, '')) <> 'female' or mom.parent_id is null then
      raise exception 'الأم لم تعد في شجرة النساء' using errcode = 'P0001', hint = 'bad_mother';
    end if;
  end if;

  if coalesce(d->>'father_id', '') <> '' then
    hid := (d->>'father_id')::uuid;
    if mom.husband_id is distinct from hid then
      raise exception 'زوج الأم تغيّر بعد الطلب' using errcode = 'P0001', hint = 'mother_changed';
    end if;
    if exists (select 1 from public.profiles x where x.id = hid) then
      raise exception 'الأب من العائلة — «ربط بالشجرة»' using errcode = 'P0001', hint = 'father_in_family';
    end if;
    select coalesce(nullif(btrim(full_name), ''), first_name) into hname from public.women_members where id = hid;
  else
    if mom.husband_id is not null then
      raise exception 'للأم زوج مسجّل الآن — يرسل العضو طلبه من جديد' using errcode = 'P0001', hint = 'mother_has_husband';
    end if;
    hname := btrim(coalesce(d->>'father_name', ''));
    if hname = '' or coalesce(btrim(d->'father'->>'first_name'), '') = '' then
      raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload';
    end if;
    insert into public.women_members (id, first_name, full_name, gender, parent_id, is_married, is_deceased,
                                      is_outside_family, sort_order)
    values (gen_random_uuid(), btrim(d->'father'->>'first_name'), hname, 'male', null, true,
            coalesce((d->'father'->>'is_deceased')::boolean, false), true, 0)
    returning id into hid;
    update public.women_members set husband_id = hid, is_married = true where id = mom.id;
  end if;

  son_first := coalesce(nullif(btrim(son.first_name), ''), split_part(btrim(coalesce(son.full_name, '')), ' ', 1));
  insert into public.women_members (id, first_name, full_name, gender, parent_id, mother_id, linked_user_id,
                                    is_deceased, sort_order)
  values (gen_random_uuid(), son_first, btrim(son_first || ' ' || hname), 'male', hid, mom.id, son.id, false,
          coalesce((select max(c.sort_order) + 1 from public.women_members c where c.parent_id = hid), 0))
  returning id into son_id;

  update public.daughter_son_lineage set completed_at = now(), women_node_id = son_id where profile_id = son.id;
  update public.admin_requests set status = 'approved', replied_by = me, replied_at = now() where id = r.id;

  insert into public.notifications (target_member_id, title, body, kind, created_by)
  values (son.id, private.daughter_sons_text('notify_completed_title', 'اكتمل حسابك'),
          'صرت في شجرة النساء تحت أمّك ' || coalesce(nullif(btrim(mom.first_name), ''), '')
          || ' وأبوك ' || hname, 'admin', me);

  return jsonb_build_object('ok', true, 'request_id', r.id, 'status', 'approved',
                            'mother_id', mom.id, 'new_mother', new_mom,
                            'husband_id', hid, 'son_node_id', son_id);
end;
$function$;

-- الحارس والبحث كما كانا
do $mig$
declare d text := pg_get_functiondef('public.guard_admin_request_insert()'::regprocedure); n text;
begin
  n := replace(d,
    $x$  if new.request_type not in ('link_request','contact_message','account_delete') and not public.is_approved_member()
     -- «بنت بنت» ترسل نسبها وهي «قيد المراجعة» — من submit_daughter_daughter_lineage فقط (20261127150000)
     and not (new.request_type = 'lineage_request' and coalesce(current_setting('app.lineage_rpc', true), '') = 'on') then$x$,
    $x$  if new.request_type not in ('link_request','contact_message','account_delete') and not public.is_approved_member() then$x$);
  if n = d then raise exception 'guard_admin_request_insert: ليس نص 20261127150000'; end if;
  execute n;
end $mig$;

do $mig$
declare d text := pg_get_functiondef('public.search_daughters_for_lineage(text)'::regprocedure); n text;
begin
  n := replace(d, 'perform private.lineage_search_caller();', 'perform private.lineage_require_open();');
  if n = d then raise exception 'search_daughters_for_lineage: ليس نص 20261127150000'; end if;
  execute n;
end $mig$;

drop function if exists public.submit_daughter_daughter_lineage(uuid, text, boolean, uuid);
drop function if exists public.my_daughter_lineage_status();
drop function if exists private.lineage_search_caller();
drop function if exists private.lineage_daughter_applicant();
drop function if exists private.lineage_names_match(text, text);
delete from public.app_config where key = 'daughter_daughters_enabled';
