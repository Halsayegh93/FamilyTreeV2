-- «هل أحد أفراد أسرتك من العائلة؟» — الزوج أو الزوجة من العائلة (موافقة المالك ٢٠٢٦-١١-٢٨، العيّنة spouse2.html «نفّذ كل شي»)
-- مطبَّق على الحي ٢٠٢٦-١١-٢٨ بعد تجربة begin…rollback بجلسة authenticated (٣٥ فحصاً: الإرسال والتعديل، طلب المعلومات، إضافة البنت
-- تحت والدها وربط الزوج، ربط الزوجة برجل من العائلة، الرفض، منع العضو، منع الهدف الخطأ، الفئة outside_spouse بعد الربط، صفر روابط محجوبة).
--
-- المسار: بعد قبول «من خارج العائلة» ← «استكمال التسجيل» ← «هل الوالدة من العائلة؟» لا ← «هل أحد أفراد أسرتك من العائلة؟»:
--   «الزوجة» (للرجل) / «الزوج» (للمرأة) ← «اسم الزوجة/الزوج الرباعي» (العائلة «المحمدعلي» ثابتة) ← submit_spouse_link(p_name)
--   ← طلب في «الوارد» من نوع lineage_request بـ kind = 'outside_spouse' (بجانب outside_typed؛ الحارس trg_guard_admin_request_insert
--   يقبل lineage_request من الدوال وحدها بـ app.lineage_rpc — لا تعديل عليه). الحساب يبقى «لم يستكمل التسجيل» (صفّ النسب كما هو)،
--   والإرسال من جديد وهو معلّق = «تعديل البيانات» (يُحدَّث الطلب نفسه ويُغلق «طلب المعلومات» المفتوح عليه).
--   «لا يوجد» = mark_outside_mother() كما كان (مقيّد).
-- الإدارة (المالك، المدير، المراقب؛ لا تقرّر في طلبك إلا المالك):
--   spouse_link_suggestions(p_request_id)  — اقتراحات من الشجرة بالاسم المكتوب + الوالد إن وُجد (للزوجة).
--   link_outside_spouse(p_request_id, p_target_id, p_wife_node_id)
--       الزوجة (صاحب الحساب رجل من خارج العائلة): p_target_id = عقدة البنت في شجرة النساء (أبوها رجل من العائلة).
--         لها زوج من خارج العائلة بلا حساب ← تُربط عقدته بالحساب (linked_user_id)؛ بلا زوج ← عقدة ذكر is_outside_family بمعرّف
--         ملفه وتُكتب husband_id للبنت. زوجها من العائلة أو له حساب آخر ← رفض (لا يُكتب فوق رابط أبداً).
--       الزوج (صاحبة الحساب امرأة من خارج العائلة): p_target_id = الرجل في شجرة الرجال (profiles). p_wife_node_id = عقدة زوجة
--         موجودة له بلا حساب تُربط، وإلا تُنشأ عقدة زوجة بمعرّف ملفها (husband_id = الرجل؛ عقدة الرجل في شجرة النساء تُنشأ إن غابت).
--   add_daughter_and_link_spouse(p_request_id, p_father_id, p_first_name) — البنت غير مضافة والوالد موجود: تُنشأ تحت والدها
--       (الاسم الكامل يكمّله trg_women_daughter_full_name) ثم link_outside_spouse في المعاملة نفسها.
--   reject_spouse_request(p_request_id, p_reason) — رفض برسالة عن الزوج/الزوجة (لا «الوالدة»).
--   «طلب معلومات من العضو»: ask_join_completion يقبل الحقل spouse_name لهذا النوع، وmy_completion_ask يرجع kind = 'spouse'.
-- بعد الربط: يُحذف صفّ daughter_son_lineage فلا يبقى «لم يستكمل»، وmy_member_category يرجع outside_spouse بقاعدته الحالية
-- (لا أب في الشجرة + عقدة مربوطة is_outside_family بلا أم) — لا تعديل عليها. حراس روابط العائلة: لا تفريغ لأي رابط، فقط إضافة.
-- ظهور الزوج للزوجة صاحبة الحساب: women_family_set_visibility(p_self, p_spouse, p_children) الموجودة (عقدتها فقط عبر
-- my_active_women_node، للإناث) — تكتب spouse_shown/children_shown نفسها؛ لا دالة جديدة.

-- ── عقدة رجل العائلة في شجرة النساء (بمعرّفه) — كما في decide_lineage_request ─────────────────────────────────────
create or replace function private.ensure_men_mirror_node(p_man uuid)
returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  gf public.profiles%rowtype;
  n  public.women_members%rowtype;
begin
  select * into n from public.women_members where id = p_man;
  if found then
    if lower(coalesce(n.gender, 'male')) <> 'male' then
      raise exception 'bad_target' using errcode = 'P0001', hint = 'bad_target';
    end if;
    return n.id;
  end if;
  select * into gf from public.profiles where id = p_man and lower(coalesce(gender, 'male')) <> 'female';
  if not found then
    raise exception 'الرجل غير موجود في الشجرة' using errcode = 'P0001', hint = 'bad_target';
  end if;
  insert into public.women_members (id, first_name, full_name, parent_id, gender, is_deceased, sort_order)
  values (gf.id, gf.first_name, coalesce(nullif(btrim(gf.full_name), ''), gf.first_name),
          (select w.id from public.women_members w where w.id = gf.father_id), 'male',
          coalesce(gf.is_deceased, false), coalesce(gf.sort_order, 0));
  return gf.id;
end;
$$;
revoke all on function private.ensure_men_mirror_node(uuid) from public, anon, authenticated;

-- ── العضو: إرسال بيانات الزوج/الزوجة (أو تعديلها وهي معلّقة) ──────────────────────────────────────────────────────
create or replace function public.submit_spouse_link(p_name text)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  me      uuid := public.current_profile_id();
  l       public.daughter_son_lineage%rowtype;
  p       public.profiles%rowtype;
  nm      text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  fam     text := 'المحمدعلي';
  rel     text;
  me_name text;
  payload jsonb;
  pend    public.admin_requests%rowtype;
  pd      jsonb;
  rid     uuid;
  edited  boolean := false;
begin
  if me is null or not public.is_approved_member() then
    raise exception 'للأعضاء المفعّلين' using errcode = '42501', hint = 'not_allowed';
  end if;
  select * into l from public.daughter_son_lineage where profile_id = me for update;
  if not found or l.completed_at is not null or l.limited_at is not null then
    raise exception 'التسجيل مكتمل' using errcode = 'P0001', hint = 'not_needed';
  end if;
  -- كتب العائلة في آخر الاسم؟ تُحذف — تُضاف «المحمدعلي» ثابتة
  nm := btrim(regexp_replace(nm, '\s+المحمد\s*علي$', ''));
  if coalesce(array_length(string_to_array(nullif(nm, ''), ' '), 1), 0) < 2 then
    raise exception 'يُرجى كتابة الاسم' using errcode = '22023', hint = 'name_required';
  end if;
  if length(nm) > 120 then
    raise exception 'الاسم طويل' using errcode = '22023', hint = 'name_too_long';
  end if;

  select * into p from public.profiles where id = me;
  rel := case when lower(coalesce(p.gender, '')) = 'female' then 'husband' else 'wife' end;
  me_name := btrim(regexp_replace(coalesce(nullif(btrim(p.full_name), ''), p.first_name, ''), '\s+', ' ', 'g'));
  payload := jsonb_build_object(
    'v', 1,
    'kind', 'outside_spouse',
    'relation', rel,
    'spouse_typed_name', nm,
    'spouse_family', fam,
    'spouse_name', nm || ' ' || fam,
    'member_name', me_name,
    'summary', case rel when 'wife' then 'الزوجة: ' else 'الزوج: ' end || nm || ' ' || fam);

  select * into pend from public.admin_requests r
   where r.request_type = 'lineage_request' and r.requester_id = me and r.status = 'pending'
   order by r.created_at desc limit 1
   for update;
  if found then
    begin
      pd := pend.details::jsonb;
    exception when others then
      pd := null;
    end;
    if pd is null or jsonb_typeof(pd) <> 'object' or pd->>'kind' is distinct from 'outside_spouse' then
      raise exception 'الطلب لدى الإدارة' using errcode = 'P0001', hint = 'already_pending';
    end if;
    perform set_config('app.lineage_rpc', 'on', true);
    update public.admin_requests set details = payload::text where id = pend.id;
    perform set_config('app.lineage_rpc', '', true);
    update public.join_completion_asks set answered_at = now() where request_id = pend.id and answered_at is null;
    rid := pend.id;
    edited := true;
  else
    if public.config_int('daughter_sons_max_resubmits', 3) > 0
       and (select count(*) from public.admin_requests r
             where r.request_type = 'lineage_request' and r.requester_id = me and r.status = 'rejected'
               and r.created_at >= l.approved_at) > public.config_int('daughter_sons_max_resubmits', 3) then
      raise exception 'تم بلوغ الحد الأقصى للمحاولات — يُرجى التواصل مع الإدارة' using errcode = 'P0001', hint = 'resubmit_limit';
    end if;
    perform set_config('app.lineage_rpc', 'on', true);
    insert into public.admin_requests (member_id, requester_id, request_type, status, details, new_value)
    values (me, me, 'lineage_request', 'pending', payload::text, null)
    returning id into rid;
    perform set_config('app.lineage_rpc', '', true);
  end if;

  insert into public.notifications (target_member_id, title, body, kind, created_by)
  select s.id,
         case when edited then 'تعديل طلب ربط' else 'طلب ربط جديد' end,
         me_name || case when edited then ' عدّل ' else ' أرسل ' end
           || case rel when 'wife' then 'اسم الزوجة' else 'اسم الزوج' end || ' — يُرجى ربطه بالشجرة',
         'admin', me
    from public.profiles s
   where s.role in ('owner', 'admin', 'monitor') and s.status = 'active' and s.id <> me;

  return rid;
end;
$$;
revoke all on function public.submit_spouse_link(text) from public, anon;
grant execute on function public.submit_spouse_link(text) to authenticated;

-- ── العضو: طلبه المعلّق (لشاشة «تم إرسال البيانات» و«تعديل البيانات») ─────────────────────────────────────────────
create or replace function public.my_spouse_request()
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  select jsonb_build_object('request_id', r.id,
                            'relation', d->>'relation',
                            'spouse_typed_name', d->>'spouse_typed_name',
                            'spouse_name', d->>'spouse_name',
                            'created_at', r.created_at)
    from public.admin_requests r
    cross join lateral (select case when r.details ~ '^\s*\{' then r.details::jsonb end as d) x
   where r.request_type = 'lineage_request'
     and r.requester_id = public.current_profile_id()
     and r.status = 'pending'
     and x.d->>'kind' = 'outside_spouse'
   order by r.created_at desc
   limit 1;
$$;
revoke all on function public.my_spouse_request() from public, anon;
grant execute on function public.my_spouse_request() to authenticated;

-- ── الإدارة: الطلب مقفولاً بعد الفحص ────────────────────────────────────────────────────────────────────────────────
create or replace function private.spouse_request_for_admin(p_request_id uuid)
returns public.admin_requests
language plpgsql
security definer
set search_path to ''
as $$
declare
  r       public.admin_requests%rowtype;
  d       jsonb;
  me      uuid := public.current_profile_id();
  my_role text := coalesce(public.current_user_role(), '');
begin
  if my_role not in ('owner', 'admin', 'monitor') then
    raise exception 'طلبات الربط للمالك والمدير والمراقب' using errcode = '42501', hint = 'not_allowed';
  end if;
  select * into r from public.admin_requests where id = p_request_id for update;
  if not found or r.request_type is distinct from 'lineage_request' then
    raise exception 'الطلب غير موجود' using errcode = 'P0001', hint = 'request_not_found';
  end if;
  begin
    d := r.details::jsonb;
  exception when others then
    d := null;
  end;
  if d is null or jsonb_typeof(d) <> 'object' or d->>'kind' is distinct from 'outside_spouse' then
    raise exception 'الطلب ليس طلب ربط زوج أو زوجة' using errcode = 'P0001', hint = 'request_not_found';
  end if;
  if r.status is distinct from 'pending' then
    raise exception 'الطلب عولج من قبل' using errcode = 'P0001', hint = 'already_handled';
  end if;
  if my_role <> 'owner' and (r.requester_id = any (array[auth.uid(), me]) or r.member_id = any (array[auth.uid(), me])) then
    raise exception 'لا تقرّر في طلبك' using errcode = '42501', hint = 'own_request';
  end if;
  return r;
end;
$$;
revoke all on function private.spouse_request_for_admin(uuid) from public, anon, authenticated;

-- ── الإدارة: الاقتراحات ─────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.spouse_link_suggestions(p_request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  r    public.admin_requests%rowtype;
  d    jsonb;
  rel  text;
  q    text[];
  me_first text;
  k    int;
  res  jsonb := '[]'::jsonb;
  fat  jsonb := '[]'::jsonb;
begin
  if coalesce(public.current_user_role(), '') not in ('owner', 'admin', 'monitor') then
    raise exception 'طلبات الربط للمالك والمدير والمراقب' using errcode = '42501', hint = 'not_allowed';
  end if;
  select * into r from public.admin_requests where id = p_request_id;
  if not found or r.request_type is distinct from 'lineage_request' then
    raise exception 'الطلب غير موجود' using errcode = 'P0001', hint = 'request_not_found';
  end if;
  begin
    d := r.details::jsonb;
  exception when others then
    d := null;
  end;
  if d is null or jsonb_typeof(d) <> 'object' or d->>'kind' is distinct from 'outside_spouse' then
    return jsonb_build_object('relation', null, 'matches', '[]'::jsonb, 'fathers', '[]'::jsonb);
  end if;
  rel := d->>'relation';
  q := private.lineage_name_words(left(coalesce(d->>'spouse_typed_name', ''), 200));
  select (private.lineage_name_words(coalesce(nullif(btrim(p.first_name), ''), split_part(btrim(coalesce(p.full_name, '')), ' ', 1))))[1]
    into me_first from public.profiles p where p.id = r.requester_id;

  for k in reverse least(coalesce(array_length(q, 1), 0), 4) .. 2 loop
    if rel = 'wife' then
      -- بنات العائلة (أبوها في شجرة الرجال) بالاسم المكتوب
      select coalesce(jsonb_agg(x.o order by x.rank, x.sort_order, x.full_name), '[]'::jsonb) into res
        from (
          select jsonb_build_object(
                   'id', w.id,
                   'full_name', coalesce(nullif(btrim(w.full_name), ''), w.first_name, ''),
                   'father_id', w.parent_id,
                   'has_account', w.linked_user_id is not null,
                   'is_deceased', coalesce(w.is_deceased, false),
                   'husband_id', w.husband_id,
                   'husband_name', coalesce(nullif(btrim(h.full_name), ''), h.first_name),
                   'husband_in_family', h.id is not null and exists (select 1 from public.profiles x where x.id = h.id),
                   'husband_has_account', h.linked_user_id is not null,
                   'can_link', h.id is null or (not exists (select 1 from public.profiles x where x.id = h.id)
                                                and h.linked_user_id is null),
                   'wife_node_id', null,
                   'matched_words', k) as o,
                 rk.rank, w.sort_order, w.full_name
            from public.women_members w
            join public.profiles f on f.id = w.parent_id
            left join public.women_members h on h.id = w.husband_id
            cross join lateral (select private.lineage_chain_rank(
                                  private.lineage_name_words(coalesce(nullif(btrim(w.full_name), ''), w.first_name)),
                                  array_to_string(q[1:k], '')) as rank) rk
           where lower(coalesce(w.gender, '')) = 'female'
             and not coalesce(w.is_web_only, false)
             and rk.rank is not null
           order by rk.rank, w.sort_order, w.full_name
           limit 10) x;
    else
      -- رجال العائلة بالاسم المكتوب (+ عقدة زوجة له بلا حساب باسمها الأول إن وُجدت)
      select coalesce(jsonb_agg(x.o order by x.rank, x.sort_order, x.full_name), '[]'::jsonb) into res
        from (
          select jsonb_build_object(
                   'id', p.id,
                   'full_name', coalesce(nullif(btrim(p.full_name), ''), p.first_name, ''),
                   'father_id', p.father_id,
                   'has_account', false,
                   'is_deceased', coalesce(p.is_deceased, false),
                   'husband_id', null, 'husband_name', null, 'husband_in_family', false, 'husband_has_account', false,
                   'can_link', true,
                   'wife_node_id', (select w.id from public.women_members w
                                     where w.husband_id = p.id and w.linked_user_id is null
                                       and lower(coalesce(w.gender, '')) = 'female'
                                       and (private.lineage_name_words(coalesce(nullif(btrim(w.first_name), ''), w.full_name)))[1] = me_first
                                     order by w.wife_order nulls last limit 1),
                   'matched_words', k) as o,
                 rk.rank, p.sort_order, p.full_name
            from public.profiles p
            cross join lateral (select private.lineage_chain_rank(
                                  private.lineage_name_words(coalesce(nullif(btrim(p.full_name), ''), p.first_name)),
                                  array_to_string(q[1:k], '')) as rank) rk
           where lower(coalesce(p.gender, 'male')) <> 'female'
             and not coalesce(p.is_hidden_from_tree, false)
             and coalesce(p.role, '') <> 'pending'
             and p.id <> r.requester_id
             and rk.rank is not null
           order by rk.rank, p.sort_order, p.full_name
           limit 10) x;
    end if;
    exit when jsonb_array_length(res) > 0;
  end loop;

  -- الوالد (للزوجة): الاسم بعد الاسم الأول في شجرة الرجال
  if rel = 'wife' and coalesce(array_length(q, 1), 0) >= 3 then
    select coalesce(jsonb_agg(x.o order by x.rank, x.sort_order), '[]'::jsonb) into fat
      from (
        select jsonb_build_object('id', p.id, 'full_name', coalesce(nullif(btrim(p.full_name), ''), p.first_name, ''),
                                  'is_deceased', coalesce(p.is_deceased, false)) as o,
               rk.rank, p.sort_order
          from public.profiles p
          cross join lateral (select private.lineage_chain_rank(
                                private.lineage_name_words(coalesce(nullif(btrim(p.full_name), ''), p.first_name)),
                                array_to_string(q[2:least(array_length(q, 1), 4)], '')) as rank) rk
         where lower(coalesce(p.gender, 'male')) <> 'female'
           and not coalesce(p.is_hidden_from_tree, false)
           and coalesce(p.role, '') <> 'pending'
           and rk.rank is not null
         order by rk.rank, p.sort_order
         limit 3) x;
  end if;

  return jsonb_build_object('relation', rel, 'typed_name', d->>'spouse_typed_name', 'spouse_name', d->>'spouse_name',
                            'matches', res, 'fathers', fat);
end;
$$;
revoke all on function public.spouse_link_suggestions(uuid) from public, anon;
grant execute on function public.spouse_link_suggestions(uuid) to authenticated;

-- ── الإدارة: الربط ──────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.link_outside_spouse(p_request_id uuid, p_target_id uuid, p_wife_node_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  me     uuid := public.current_profile_id();
  r      public.admin_requests%rowtype;
  d      jsonb;
  rel    text;
  m      public.profiles%rowtype;
  w      public.women_members%rowtype;
  h      public.women_members%rowtype;
  man    public.profiles%rowtype;
  mfirst text;
  mfull  text;
  node   uuid;
  spouse uuid;
  sname  text;
begin
  r := private.spouse_request_for_admin(p_request_id);
  d := r.details::jsonb;
  rel := d->>'relation';
  if p_target_id is null or rel not in ('wife', 'husband') then
    raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload';
  end if;

  select * into m from public.profiles where id = r.requester_id for update;
  if not found then
    raise exception 'صاحب الطلب لم يعد له حساب' using errcode = 'P0001', hint = 'requester_gone';
  end if;
  if coalesce(m.status, '') in ('frozen', 'deleted') then
    raise exception 'الحساب موقوف' using errcode = 'P0001', hint = 'account_frozen';
  end if;
  if m.father_id is not null then
    raise exception 'الحساب مربوط بشجرة الرجال' using errcode = 'P0001', hint = 'has_father';
  end if;
  if exists (select 1 from public.women_members x where x.linked_user_id = m.id or x.id = m.id) then
    raise exception 'الحساب مربوط بشجرة النساء من قبل' using errcode = 'P0001', hint = 'already_linked';
  end if;
  if not exists (select 1 from public.daughter_son_lineage l
                  where l.profile_id = m.id and l.completed_at is null and l.limited_at is null) then
    raise exception 'التسجيل مكتمل' using errcode = 'P0001', hint = 'not_needed';
  end if;
  mfull := btrim(regexp_replace(coalesce(nullif(btrim(m.full_name), ''), m.first_name, ''), '\s+', ' ', 'g'));
  mfirst := coalesce(nullif(btrim(m.first_name), ''), split_part(mfull, ' ', 1));

  if rel = 'wife' then
    -- صاحب الحساب رجل من خارج العائلة ← البنت عقدة في شجرة النساء أبوها رجل من العائلة
    select * into w from public.women_members where id = p_target_id for update;
    if not found or lower(coalesce(w.gender, '')) <> 'female' or w.parent_id is null
       or not exists (select 1 from public.profiles f where f.id = w.parent_id) then
      raise exception 'ليست من بنات العائلة في الشجرة' using errcode = 'P0001', hint = 'bad_target';
    end if;
    if w.husband_id is not null then
      select * into h from public.women_members where id = w.husband_id for update;
      if exists (select 1 from public.profiles x where x.id = h.id) then
        raise exception 'زوجها من العائلة — لا يُكتب فوقه' using errcode = 'P0001', hint = 'spouse_in_family';
      end if;
      if h.linked_user_id is not null then
        raise exception 'لزوجها حساب آخر في التطبيق' using errcode = 'P0001', hint = 'spouse_has_account';
      end if;
      update public.women_members
         set linked_user_id = m.id, is_outside_family = true
       where id = h.id;
      node := h.id;
    else
      insert into public.women_members (id, first_name, full_name, gender, parent_id, is_married, is_deceased,
                                        is_outside_family, sort_order, linked_user_id)
      values (m.id, mfirst, mfull, 'male', null, true, false, true, 0, m.id)
      returning id into node;
      update public.women_members set husband_id = node, is_married = true where id = w.id;
    end if;
    spouse := w.id;
    sname := coalesce(nullif(btrim(w.first_name), ''), split_part(coalesce(w.full_name, ''), ' ', 1));
  else
    -- صاحبة الحساب امرأة من خارج العائلة ← الزوج رجل في شجرة الرجال
    select * into man from public.profiles where id = p_target_id;
    if not found or lower(coalesce(man.gender, 'male')) = 'female' or coalesce(man.role, '') = 'pending'
       or exists (select 1 from public.daughter_son_lineage x where x.profile_id = man.id) then
      raise exception 'الرجل غير موجود في شجرة العائلة' using errcode = 'P0001', hint = 'bad_target';
    end if;
    perform private.ensure_men_mirror_node(man.id);
    if p_wife_node_id is not null then
      select * into w from public.women_members where id = p_wife_node_id for update;
      if not found or w.husband_id is distinct from man.id or lower(coalesce(w.gender, '')) <> 'female' then
        raise exception 'ليست زوجة له في الشجرة' using errcode = 'P0001', hint = 'bad_target';
      end if;
      if w.linked_user_id is not null then
        raise exception 'لها حساب آخر في التطبيق' using errcode = 'P0001', hint = 'spouse_has_account';
      end if;
      update public.women_members set linked_user_id = m.id where id = w.id;
      node := w.id;
    else
      insert into public.women_members (id, first_name, full_name, gender, parent_id, husband_id, is_married, is_deceased,
                                        is_outside_family, sort_order, linked_user_id)
      values (m.id, mfirst, mfull, 'female', null, man.id, true, false, true, 0, m.id)
      returning id into node;
    end if;
    spouse := man.id;
    sname := coalesce(nullif(btrim(man.first_name), ''), split_part(coalesce(man.full_name, ''), ' ', 1));
  end if;

  -- «لم يستكمل التسجيل» يُغلق: الفئة تصير outside_spouse (my_member_category)
  delete from public.daughter_son_lineage where profile_id = m.id;
  update public.profiles
     set role = case when coalesce(role, 'pending') = 'pending' then 'member' else role end,
         status = 'active',
         is_hidden_from_tree = true
   where id = m.id;
  update public.admin_requests set status = 'approved', replied_by = me, replied_at = now() where id = r.id;
  update public.admin_requests
     set status = 'approved', replied_by = me, replied_at = now()
   where member_id = m.id and request_type in ('join_request', 'link_request') and status = 'pending';

  insert into public.notifications (target_member_id, title, body, kind, created_by)
  values (m.id, 'اكتمل التسجيل',
          'تم ربط حسابك بالشجرة ' || case rel when 'wife' then 'بالزوجة ' else 'بالزوج ' end || coalesce(sname, ''),
          'admin', me);

  return jsonb_build_object('ok', true, 'request_id', r.id, 'relation', rel, 'node_id', node, 'spouse_id', spouse);
end;
$$;
revoke all on function public.link_outside_spouse(uuid, uuid, uuid) from public, anon;
grant execute on function public.link_outside_spouse(uuid, uuid, uuid) to authenticated;

-- ── الإدارة: البنت غير مضافة والوالد موجود ← إضافتها تحت والدها وربط الزوج ─────────────────────────────────────────
create or replace function public.add_daughter_and_link_spouse(p_request_id uuid, p_father_id uuid, p_first_name text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  r     public.admin_requests%rowtype;
  d     jsonb;
  first text;
  wid   uuid;
  res   jsonb;
begin
  r := private.spouse_request_for_admin(p_request_id);
  d := r.details::jsonb;
  if d->>'relation' is distinct from 'wife' then
    raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload';
  end if;
  first := btrim(regexp_replace(coalesce(nullif(btrim(p_first_name), ''), split_part(btrim(coalesce(d->>'spouse_typed_name', '')), ' ', 1)),
                                '\s+', ' ', 'g'));
  if first = '' or position(' ' in first) > 0 or length(first) > 40 then
    raise exception 'الاسم الأول غير صحيح' using errcode = '22023', hint = 'name_required';
  end if;
  if not exists (select 1 from public.profiles f where f.id = p_father_id and lower(coalesce(f.gender, 'male')) <> 'female'
                                               and coalesce(f.role, '') <> 'pending') then
    raise exception 'الوالد غير موجود في شجرة العائلة' using errcode = 'P0001', hint = 'bad_target';
  end if;
  perform private.ensure_men_mirror_node(p_father_id);
  insert into public.women_members (id, first_name, full_name, gender, parent_id, is_married, is_deceased, sort_order)
  values (gen_random_uuid(), first, first, 'female', p_father_id, true, false,
          coalesce((select max(c.sort_order) + 1 from public.women_members c where c.parent_id = p_father_id), 0))
  returning id into wid;
  res := public.link_outside_spouse(p_request_id, wid, null);
  return res || jsonb_build_object('new_daughter_id', wid);
end;
$$;
revoke all on function public.add_daughter_and_link_spouse(uuid, uuid, text) from public, anon;
grant execute on function public.add_daughter_and_link_spouse(uuid, uuid, text) to authenticated;

-- ── الإدارة: الرفض ──────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.reject_spouse_request(p_request_id uuid, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  me     uuid := public.current_profile_id();
  r      public.admin_requests%rowtype;
  reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  r := private.spouse_request_for_admin(p_request_id);
  update public.admin_requests
     set status = 'rejected', admin_reply = reason, replied_by = me, replied_at = now()
   where id = r.id;
  insert into public.notifications (target_member_id, title, body, kind, created_by)
  values (r.requester_id, 'يُرجى مراجعة البيانات وإرسالها من جديد',
          'يُرجى فتح «استكمال التسجيل» ومراجعة بيانات الزوج أو الزوجة.' || coalesce(E'\nالسبب: ' || reason, ''),
          'request_rejected', me);
  return jsonb_build_object('ok', true, 'request_id', r.id, 'status', 'rejected');
end;
$$;
revoke all on function public.reject_spouse_request(uuid, text) from public, anon;
grant execute on function public.reject_spouse_request(uuid, text) to authenticated;

-- ── «طلب معلومات من العضو»: حقل اسم الزوج/الزوجة ──────────────────────────────────────────────────────────────────
create or replace function public.join_completion_field_label(p_field text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $$
  select case p_field
    when 'full_name'   then 'الاسم الرباعي'
    when 'birth_date'  then 'تاريخ الميلاد'
    when 'gender'      then 'الجنس'
    when 'family'      then 'العائلة'
    when 'photo'       then 'الصورة الشخصية'
    when 'mother_name' then 'اسم الوالدة'
    when 'spouse_name' then 'اسم الزوج أو الزوجة'
    else p_field end;
$$;

create or replace function public.ask_join_completion(p_request_id uuid, p_fields text[], p_note text default null)
 returns uuid
 language plpgsql
 security definer
 set search_path to 'public'
as $$
declare
  me      uuid := public.current_profile_id();
  r       public.admin_requests%rowtype;
  allowed text[];
  fields  text[];
  f       text;
  note    text := nullif(btrim(regexp_replace(coalesce(p_note, ''), '\s+', ' ', 'g')), '');
  items   text;
  is_spouse boolean := false;
begin
  if coalesce(public.current_user_role(), '') not in ('owner', 'admin', 'monitor') then
    raise exception 'طلب استكمال البيانات للمالك والمدير والمراقب' using errcode = '42501', hint = 'not_allowed';
  end if;
  select * into r from public.admin_requests where id = p_request_id for update;
  if not found or r.request_type not in ('join_request', 'link_request', 'lineage_request') then
    raise exception 'الطلب غير موجود' using errcode = 'P0001', hint = 'request_not_found';
  end if;
  if r.status is distinct from 'pending' then
    raise exception 'الطلب عولج من قبل' using errcode = 'P0001', hint = 'already_handled';
  end if;
  -- 20261128150000: طلب ربط الزوج/الزوجة (kind outside_spouse) ← اسمه وحده
  is_spouse := r.request_type = 'lineage_request' and coalesce(r.details, '') ~ '^\s*\{'
               and (r.details::jsonb)->>'kind' = 'outside_spouse';
  allowed := case when is_spouse then array['spouse_name']
                  when r.request_type = 'lineage_request' then array['mother_name']
                  else array['full_name', 'birth_date', 'gender', 'family', 'photo'] end;
  foreach f in array coalesce(p_fields, array[]::text[]) loop
    f := lower(btrim(coalesce(f, '')));
    continue when f = '';
    if not (f = any (allowed)) then
      raise exception 'حقل غير معروف: %', f using errcode = '22023', hint = 'bad_field';
    end if;
    if fields is null or not (f = any (fields)) then fields := array_append(fields, f); end if;
  end loop;
  if fields is null then
    raise exception 'يُرجى تحديد البيانات الناقصة' using errcode = '22023', hint = 'fields_required';
  end if;
  if length(coalesce(note, '')) > 200 then
    raise exception 'الملاحظة طويلة — ٢٠٠ حرف على الأكثر' using errcode = '22023', hint = 'note_too_long';
  end if;

  -- طلب مفتوح واحد لكل طلب: الجديد يحلّ محلّ القديم
  delete from public.join_completion_asks where request_id = r.id and answered_at is null;
  insert into public.join_completion_asks (request_id, member_id, fields, note, asked_by)
  values (r.id, r.member_id, fields, note, me);

  items := array_to_string(array(select public.join_completion_field_label(x) from unnest(fields) x), '، ');
  insert into public.notifications (target_member_id, title, body, kind, created_by)
  values (r.member_id, 'يُرجى استكمال البيانات',
          'يُرجى استكمال البيانات: ' || items || '.' || coalesce(E'\n' || note, ''), 'join_completion', me);
  return r.id;
end;
$$;

create or replace function public.my_completion_ask()
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $$
  select jsonb_build_object(
           'request_id', a.request_id,
           'kind', case when r.request_type = 'lineage_request'
                             and coalesce(r.details, '') ~ '^\s*\{' and (r.details::jsonb)->>'kind' = 'outside_spouse' then 'spouse'
                        when r.request_type = 'lineage_request' then 'lineage'
                        else 'join' end,
           'fields', to_jsonb(a.fields),
           'note', a.note,
           'asked_at', a.asked_at)
    from public.join_completion_asks a
    join public.admin_requests r on r.id = a.request_id
   where a.member_id = public.current_profile_id()
     and a.answered_at is null
     and r.status = 'pending'
   order by a.asked_at desc
   limit 1;
$$;
