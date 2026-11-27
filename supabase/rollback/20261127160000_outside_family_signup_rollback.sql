-- تراجع 20261127160000_outside_family_signup — يعيد الحي كما كان قبله حرفياً (20261127150000).
-- العُقد التي أُنشئت بعده تبقى (لا فكّ لأي رابط). قبل التراجع: ارفض طلبات النسب المعلّقة بنوع outside_typed (لا يقبلها
-- القرار القديم)، وراجع صفوف daughter_son_lineage لبنات قُبلن «من خارج العائلة» (القفل يبقى عليهن):
--   select id from admin_requests where request_type = 'lineage_request' and status = 'pending' and details like '%outside_typed%';
--   select d.profile_id from daughter_son_lineage d join profiles p on p.id = d.profile_id where lower(p.gender) = 'female';

do $mig$
declare d text := pg_get_functiondef('public.approve_join_as_daughter_son(uuid)'::regprocedure); n text;
begin
  n := replace(d, $x$  -- الأنثى أيضاً (بنت البنت من خارج العائلة، 20261127160000) — «استكمال التسجيل» بعد القبول
$x$, $x$  if lower(coalesce(p.gender, 'male')) = 'female' then
    raise exception 'صاحبة الطلب أنثى — تُربط بشجرة النساء' using errcode = 'P0001', hint = 'not_male';
  end if;
$x$);
  n := replace(n, $x$'تم قبول طلب انضمامك. يُرجى فتح التطبيق واستكمال التسجيل باختيار الوالدة وكتابة اسم الوالد.'$x$,
                  $x$'تم قبول طلب انضمامك — افتح التطبيق واضغط «أكمل حسابك»: اختر أمّك واكتب اسم أبوك'$x$);
  if n = d then raise exception 'approve_join_as_daughter_son: نص الحي تغيّر — راجع التراجع'; end if;
  execute n;
end $mig$;

drop function if exists public.submit_outside_lineage(text);
drop function if exists public.mark_outside_mother();
drop function if exists public.lineage_mother_suggestions(uuid);
drop function if exists public.decide_lineage_request(uuid, text, text, uuid);

-- قرار الإدارة كما في 20261127150000 (بثلاثة معاملات) وصلاحياته كما في 20261107120000
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
  hus      public.women_members%rowtype;
  gfid     uuid;
  mfirst   text;
  hid      uuid;
  hname    text;
  son_id   uuid;
  son_first text;
  new_mom  boolean := false;
  is_dd    boolean := false;
  reused   boolean := false;
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

  begin
    d := r.details::jsonb;
  exception when others then
    d := null;
  end;
  is_dd := d is not null and jsonb_typeof(d) = 'object' and d->>'kind' = 'daughter_daughter';

  if decision = 'reject' then
    update public.admin_requests
       set status = 'rejected', admin_reply = reason, replied_by = me, replied_at = now()
     where id = r.id;
    if is_dd then
      -- طلب انضمامها يبقى معلّقاً — ترسل من جديد أو تربطها الإدارة بطريق آخر
      insert into public.notifications (target_member_id, title, body, kind, created_by)
      values (r.requester_id, 'راجعي بياناتك وأرسليها من جديد',
              'افتحي التطبيق وراجعي اختيار أمّك واسم أبيك' || coalesce(E'\nالسبب: ' || reason, ''), 'request_rejected', me);
    else
      insert into public.notifications (target_member_id, title, body, kind, created_by)
      values (r.requester_id,
              private.daughter_sons_text('notify_rejected_title', 'راجع بياناتك وأرسلها من جديد'),
              private.daughter_sons_text('notify_rejected_body', 'افتح «أكمل حسابك» وراجع اختيار أمّك وأبوك')
                || coalesce(E'\nالسبب: ' || reason, ''), 'request_rejected', me);
    end if;
    return jsonb_build_object('ok', true, 'request_id', r.id, 'status', 'rejected');
  end if;

  if d is null or jsonb_typeof(d) <> 'object' then
    raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload';
  end if;

  -- ═══ «بنت بنت» ═══
  if is_dd then
    select * into son from public.profiles where id = r.requester_id for update;
    if not found then
      raise exception 'صاحبة الطلب لم يعد لها حساب' using errcode = 'P0001', hint = 'requester_gone';
    end if;
    if lower(coalesce(son.gender, '')) <> 'female' then
      raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload';
    end if;
    if coalesce(son.status, '') in ('frozen', 'deleted') then
      raise exception 'الحساب موقوف' using errcode = 'P0001', hint = 'account_frozen';
    end if;
    if son.father_id is not null then
      raise exception 'الحساب مربوط بشجرة الرجال' using errcode = 'P0001', hint = 'has_father';
    end if;
    if exists (select 1 from public.women_members w where w.id = son.id or w.linked_user_id = son.id) then
      raise exception 'الحساب مربوط بشجرة النساء من قبل' using errcode = 'P0001', hint = 'already_linked';
    end if;
    if coalesce(d->>'mother_id', '') = '' then
      raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload';
    end if;
    select * into mom from public.women_members where id = (d->>'mother_id')::uuid for update;
    if not found or lower(coalesce(mom.gender, '')) <> 'female' or mom.parent_id is null
       or not exists (select 1 from public.women_members f
                       where f.id = mom.parent_id and lower(coalesce(f.gender, 'male')) = 'male') then
      raise exception 'الأم لم تعد في شجرة النساء' using errcode = 'P0001', hint = 'bad_mother';
    end if;

    if mom.husband_id is not null then
      select * into hus from public.women_members where id = mom.husband_id;
      if exists (select 1 from public.profiles x where x.id = hus.id)
         or (hus.parent_id is not null and not coalesce(hus.is_outside_family, false)) then
        raise exception 'زوج الأم من العائلة — تُربط تحت أبيها من «ربط بشجرة النساء»'
          using errcode = 'P0001', hint = 'father_in_family';
      end if;
    end if;

    if coalesce(d->>'father_id', '') <> '' then
      hid := (d->>'father_id')::uuid;
      if mom.husband_id is distinct from hid then
        raise exception 'زوج الأم تغيّر بعد الطلب' using errcode = 'P0001', hint = 'mother_changed';
      end if;
      hname := coalesce(nullif(btrim(hus.full_name), ''), hus.first_name);
      reused := true;
    else
      hname := btrim(regexp_replace(coalesce(d->>'father_name', ''), '\s+', ' ', 'g'));
      if hname = '' then
        raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload';
      end if;
      if mom.husband_id is not null then
        -- لا يُكتب فوق زوج مختلف أبداً: يُعاد إن تطابق الاسم، وإلا الإدارة تصلح يدوياً
        if not private.lineage_names_match(hname, coalesce(nullif(btrim(hus.full_name), ''), hus.first_name)) then
          raise exception 'لأمّها زوج مسجّل باسم آخر (%) — صحّح الشجرة يدوياً أو ارفض الطلب',
                coalesce(nullif(btrim(hus.full_name), ''), hus.first_name)
            using errcode = 'P0001', hint = 'mother_has_other_husband';
        end if;
        hid := hus.id;
        hname := coalesce(nullif(btrim(hus.full_name), ''), hus.first_name);
        reused := true;
      else
        insert into public.women_members (id, first_name, full_name, gender, parent_id, is_married, is_deceased,
                                          is_outside_family, sort_order)
        values (gen_random_uuid(), split_part(hname, ' ', 1), hname, 'male', null, true,
                coalesce((d->'father'->>'is_deceased')::boolean, (d->>'father_is_deceased')::boolean, false), true, 0)
        returning id into hid;
        update public.women_members set husband_id = hid, is_married = true where id = mom.id;
      end if;
    end if;

    -- عقدتها بمعرّف ملفها (النسخ القديمة تجد عقدة الشخص بمعرّفه)، وis_outside_family يحسبه السيرفر من أبيها
    son_first := coalesce(nullif(btrim(son.first_name), ''), split_part(btrim(coalesce(son.full_name, '')), ' ', 1));
    insert into public.women_members (id, first_name, full_name, gender, parent_id, mother_id, linked_user_id,
                                      is_deceased, sort_order)
    values (son.id, son_first, btrim(son_first || ' ' || hname), 'female', hid, mom.id, son.id, false,
            coalesce((select max(c.sort_order) + 1 from public.women_members c where c.parent_id = hid), 0))
    returning id into son_id;

    update public.profiles
       set role = case when coalesce(role, 'pending') = 'pending' then 'member' else role end,
           status = 'active',
           is_hidden_from_tree = true
     where id = son.id;

    update public.admin_requests set status = 'approved', replied_by = me, replied_at = now() where id = r.id;
    update public.admin_requests
       set status = 'approved', replied_by = me, replied_at = now()
     where member_id = son.id and request_type in ('join_request', 'link_request') and status = 'pending';

    insert into public.notifications (target_member_id, title, body, kind, created_by)
    values (son.id, 'مرحباً بك في العائلة', 'تم قبول طلب انضمامك وربطك بشجرة النساء', 'join_approved', me);

    return jsonb_build_object('ok', true, 'request_id', r.id, 'status', 'approved', 'kind', 'daughter_daughter',
                              'mother_id', mom.id, 'husband_id', hid, 'husband_reused', reused,
                              'node_id', son_id);
  end if;

  -- ═══ «ابن بنت» (كما في 20261108090000، وعقدته الآن بمعرّف ملفه) ═══
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
  if exists (select 1 from public.women_members w where w.linked_user_id = son.id or w.id = son.id) then
    raise exception 'الحساب مربوط بشجرة النساء من قبل' using errcode = 'P0001', hint = 'already_linked';
  end if;

  if new_mom then
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
  values (son.id, son_first, btrim(son_first || ' ' || hname), 'male', hid, mom.id, son.id, false,
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

revoke all on function public.decide_lineage_request(uuid, text, text) from public, anon;
grant execute on function public.decide_lineage_request(uuid, text, text) to authenticated;

-- القفل وحالة النسب كما في 20261108090000 / 20261107120000، ثم العمود والإعداد
create or replace function public.lineage_locked(p_section text)
 returns boolean
 language sql
 stable
 security definer
 set search_path to ''
as $function$
  select exists (select 1 from public.daughter_son_lineage d
                  where d.profile_id = public.current_profile_id() and d.completed_at is null)
     and coalesce(public.current_user_role(), '') not in ('owner', 'admin', 'monitor', 'supervisor')
     and coalesce((select case when jsonb_typeof(c.value) = 'array' then c.value ? p_section end
                     from public.app_config c where c.key = 'daughter_sons_locked_sections'),
                  p_section = any (array['diwaniyas', 'projects', 'library', 'women_tree', 'member_details']));
$function$;
comment on function public.lineage_locked(text) is
  'Caller is a daughter''s son whose «أكمل حسابك» is not approved yet and the section is in app_config.daughter_sons_locked_sections. Used by RESTRICTIVE select policies.';

create or replace function public.my_lineage_status()
 returns jsonb
 language sql
 stable
 security definer
 set search_path to 'public'
as $function$
  with me as (select public.current_profile_id() as id),
  l as (select d.* from public.daughter_son_lineage d, me where d.profile_id = me.id),
  pend as (select r.id from public.admin_requests r, me
            where r.request_type = 'lineage_request' and r.requester_id = me.id and r.status = 'pending'
            order by r.created_at desc limit 1),
  rej as (select r.admin_reply, r.replied_at from public.admin_requests r, me
           where r.request_type = 'lineage_request' and r.requester_id = me.id and r.status = 'rejected'
           order by r.replied_at desc nulls last, r.created_at desc limit 1)
  select jsonb_build_object(
    'flagged', exists (select 1 from l),
    'needs', exists (select 1 from l where l.completed_at is null) and not exists (select 1 from pend),
    'pending', exists (select 1 from pend),
    'pending_request_id', (select id from pend),
    'completed', exists (select 1 from l where l.completed_at is not null),
    'rejected_reason', case when exists (select 1 from l where l.completed_at is null)
                            then (select nullif(btrim(coalesce(admin_reply, '')), '') from rej) end,
    'was_rejected', exists (select 1 from l where l.completed_at is null) and exists (select 1 from rej));
$function$;

alter table public.daughter_son_lineage drop column if exists limited_at;
delete from public.app_config where key = 'outside_member_locked_sections';

do $mig$
declare d text := pg_get_functiondef('private.lineage_daughter_applicant()'::regprocedure); n text;
begin
  n := replace(d, $x$                   and (coalesce(r.details, '') like '%|father_id:%'
                        -- سجّلت بعد 20261127160000: «من العائلة» أو «من خارج العائلة»
                        or coalesce(r.details, '') like '%|family_signup:1%'
                        or coalesce(r.details, '') like '%|outside_family:1%')) then$x$,
                  $x$                   and coalesce(r.details, '') like '%|father_id:%') then$x$);
  if n = d then raise exception 'lineage_daughter_applicant: نص الحي تغيّر — راجع التراجع'; end if;
  execute n;
end $mig$;
