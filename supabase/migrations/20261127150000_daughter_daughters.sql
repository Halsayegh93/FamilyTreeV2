-- «بنت بنت العائلة» — طلب المالك ٢٠٢٦-١١-٢٧: «طبق الالية الحالية للتطبيق اذا بنت بنت العائلة تبي تدخل التطبيق»
-- مطبَّق على الحي ٢٠٢٦-١١-٢٧ بعد تجربة begin…rollback (عقد حسين وأسماء وعبدالعزيز بقيت بعد تعديل ملفاتهم)؛ تجربة node ٧٥/٧٥.
-- NOT APPLIED — يطبّقه المدير بعد المراجعة. التطبيقات تعمل قبله (البطاقة الجديدة تختفي إن غابت الدوال — PGRST202).
--
-- نفس آلية «ابن بنت» (20261107120000 · 20261108090000) للأنثى التي أبوها ليس في الشجرة وأمّها من بنات العائلة.
-- الفرق: الابن يُقبل أولاً ثم يكمل حسابه؛ البنت تُرسل نسبها وهي «قيد المراجعة» والموافقة عليه هي قبول انضمامها.
--
--  ١) `daughter_daughters_enabled` (app_config، افتراضي مفعّل).
--  ٢) `private.lineage_daughter_applicant()`: أنثى معلّقة، بلا أب، بلا عقدة في شجرة النساء، ولم تختر أباً عند التسجيل.
--  ٣) `search_daughters_for_lineage`: تقبلها أيضاً (نفس قاعدة الخصوصية: لا نتائج قبل الاسم الثلاثي، ١٠ بحد أقصى).
--  ٤) `my_daughter_lineage_status()` لشاشة الانتظار، و`submit_daughter_daughter_lineage(...)` ← `lineage_request`
--     بحمولة `kind = daughter_daughter` (الحارس يقبله من الدالة فقط، ولو كانت «قيد المراجعة»).
--  ٥) `decide_lineage_request`: فرع البنت عند الموافقة —
--       أبوها: زوج الأم المسجّل (يُعاد إن تطابق الاسم)، وإلا عقدة رجل من خارج العائلة زوجاً للأم.
--       لا يُكتب فوق زوج مختلف أبداً (hint = mother_has_other_husband — الإدارة تصلح يدوياً).
--       عقدتها: id = معرّف ملفها، linked_user_id = ملفها، parent_id = أبوها، mother_id = أمّها، أنثى.
--       ملفها: عضو مفعّل (مخفي من شجرة الرجال)، طلب النسب وطلب الانضمام/الربط يُغلقان «مقبول»، إشعار join_approved.
--     وفرع الابن: عقدته من الحين id = معرّف ملفه (النسخ القديمة تجد عقدة الشخص بمعرّفه) — الصفوف الموجودة كما هي.
--  ٦) `sync_profile_update_to_women`: كان يحذف عقدة بمعرّف الملف بلا أب ولا تابعين عند أي تعديل للاسم/الإخفاء —
--     عقدة مربوطة بحساب صاحبها (`linked_user_id = id`) لا تُحذف ولا تُخفى ولا يُغيَّر اسمها؛ الوفاة فقط تُنقل.
--     (يحمي «أسماء حسن حسين الموسى» 8070fd5c… المضافة يدوياً اليوم.)
--
-- الهوية من current_profile_id() فقط. لا فكّ لأي رابط. التراجع: rollback/20261127150000_daughter_daughters_rollback.sql
-- تجربة: cd supabase/tests/family_links && node daughter_daughters.test.mjs

-- ── ١) الإعداد ──
insert into public.app_config (key, value, default_value, kind, category, label_ar, help_ar, is_public, sort, min_value, max_value)
values
  ('daughter_daughters_enabled', 'true'::jsonb, 'true'::jsonb, 'bool', 'tree',
   'بنات البنات من خارج العائلة',
   'مفعّل: المسجّلة التي لم تجد أباها في الشجرة تختار أمّها من بنات العائلة وتكتب اسم أبيها، والإدارة تؤكّد من «الوارد». مطفأ: يختفي الخيار (والطلبات المعلّقة تبقى للقرار).',
   false, 74, null, null)
on conflict (key) do nothing;

-- ── ٢) مطابقة الاسم المكتوب لاسم زوج الأم المسجّل ──
-- نفس التطبيع (lineage_name_words). الاسم الأول متطابق، والأقصر كلماته بالترتيب داخل الأطول
-- («حسن حسين الموسى» = «حسن حسين علي الموسى»). كلمة واحدة لا تطابق إلا كلمة واحدة مثلها.
create or replace function private.lineage_names_match(p_a text, p_b text)
 returns boolean
 language plpgsql
 immutable
 set search_path to ''
as $function$
declare
  a text[] := private.lineage_name_words(p_a);
  b text[] := private.lineage_name_words(p_b);
  s text[];
  l text[];
  i int := 1;
  w text;
begin
  if coalesce(array_length(a, 1), 0) = 0 or coalesce(array_length(b, 1), 0) = 0 then return false; end if;
  if a[1] <> b[1] then return false; end if;
  if array_length(a, 1) <= array_length(b, 1) then s := a; l := b; else s := b; l := a; end if;
  if array_length(s, 1) = 1 then return array_length(l, 1) = 1; end if;
  foreach w in array l loop
    if i <= array_length(s, 1) and s[i] = w then i := i + 1; end if;
  end loop;
  return i > array_length(s, 1);
end;
$function$;
revoke all on function private.lineage_names_match(text, text) from public, anon, authenticated;

-- ── ٣) من تحق لها «بنت بنت» — وإلا 42501/P0001 ──
create or replace function private.lineage_daughter_applicant()
 returns uuid
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
declare
  me uuid := public.current_profile_id();
  p  public.profiles%rowtype;
begin
  if not public.config_bool('daughter_daughters_enabled', true) then
    raise exception 'الخيار مطفأ من الإعدادات' using errcode = 'P0001', hint = 'feature_off';
  end if;
  select * into p from public.profiles where id = me;
  if me is null or not found
     or lower(coalesce(p.gender, '')) <> 'female'
     or coalesce(p.role, 'pending') <> 'pending'
     or coalesce(p.status, 'pending') in ('frozen', 'deleted')
     or p.father_id is not null
     or exists (select 1 from public.women_members w where w.id = me or w.linked_user_id = me)
     -- اختارت أباها من الشجرة عند التسجيل ← بنت من العائلة تُربط تحته، لا «بنت بنت»
     or exists (select 1 from public.admin_requests r
                 where r.member_id = me and r.request_type in ('join_request', 'link_request') and r.status = 'pending'
                   and coalesce(r.details, '') like '%|father_id:%') then
    raise exception 'لمن تسجّلت ولم تجد أباها في الشجرة' using errcode = '42501', hint = 'not_allowed';
  end if;
  return me;
end;
$function$;
revoke all on function private.lineage_daughter_applicant() from public, anon, authenticated;

-- بحث الأم: ابن البنت الذي يكمل حسابه، أو المتقدّمة «بنت بنت»
create or replace function private.lineage_search_caller()
 returns uuid
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
declare me uuid := public.current_profile_id();
begin
  if me is not null and public.is_approved_member()
     and exists (select 1 from public.daughter_son_lineage d where d.profile_id = me and d.completed_at is null) then
    return me;
  end if;
  return private.lineage_daughter_applicant();
end;
$function$;
revoke all on function private.lineage_search_caller() from public, anon, authenticated;

do $mig$
declare d text := pg_get_functiondef('public.search_daughters_for_lineage(text)'::regprocedure); n text;
begin
  n := replace(d, 'perform private.lineage_require_open();', 'perform private.lineage_search_caller();');
  if n = d then raise exception 'search_daughters_for_lineage: نص الحي تغيّر — راجع الترحيل'; end if;
  execute n;
end $mig$;

-- ── ٤) الحارس: «طلب النسب» من الدالة يُقبل من «قيد المراجعة» (البنت ترسله قبل تفعيل حسابها) ──
do $mig$
declare d text := pg_get_functiondef('public.guard_admin_request_insert()'::regprocedure); n text;
begin
  n := replace(d,
    $x$  if new.request_type not in ('link_request','contact_message','account_delete') and not public.is_approved_member() then$x$,
    $x$  if new.request_type not in ('link_request','contact_message','account_delete') and not public.is_approved_member()
     -- «بنت بنت» ترسل نسبها وهي «قيد المراجعة» — من submit_daughter_daughter_lineage فقط (20261127150000)
     and not (new.request_type = 'lineage_request' and coalesce(current_setting('app.lineage_rpc', true), '') = 'on') then$x$);
  if n = d then raise exception 'guard_admin_request_insert: نص الحي تغيّر — راجع الترحيل'; end if;
  execute n;
end $mig$;

-- ── ٥) حالة «بنت بنت» لشاشة الانتظار ──
create or replace function public.my_daughter_lineage_status()
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  me   uuid := public.current_profile_id();
  ok   boolean := true;
  pend uuid;
  rej  public.admin_requests%rowtype;
begin
  begin
    perform private.lineage_daughter_applicant();
  exception when others then
    ok := false;
  end;
  select r.id into pend from public.admin_requests r
   where r.request_type = 'lineage_request' and r.requester_id = me and r.status = 'pending'
   order by r.created_at desc limit 1;
  select * into rej from public.admin_requests r
   where r.request_type = 'lineage_request' and r.requester_id = me and r.status = 'rejected'
   order by r.replied_at desc nulls last, r.created_at desc limit 1;
  return jsonb_build_object(
    'eligible', ok,
    'pending', pend is not null,
    'pending_request_id', pend,
    'was_rejected', ok and pend is null and rej.id is not null,
    'rejected_reason', case when ok and pend is null then nullif(btrim(coalesce(rej.admin_reply, '')), '') end);
end;
$function$;

-- ── ٦) البنت: أمّها + أبوها ← طلب النسب ──
create or replace function public.submit_daughter_daughter_lineage(
  p_mother_id uuid,
  p_father_full_name text default null,
  p_father_deceased boolean default false,
  p_father_id uuid default null)
 returns uuid
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  me      uuid := private.lineage_daughter_applicant();
  mom     public.women_members%rowtype;
  h       public.women_members%rowtype;
  fl      text := btrim(regexp_replace(coalesce(p_father_full_name, ''), '\s+', ' ', 'g'));
  minw    int;
  fname   text;
  fdead   boolean;
  h_in    boolean := false;
  same    boolean;
  mname   text;
  me_name text;
  payload jsonb;
  rid     uuid;
begin
  if exists (select 1 from public.admin_requests r
              where r.request_type = 'lineage_request' and r.requester_id = me and r.status = 'pending') then
    raise exception 'طلبك عند الإدارة' using errcode = 'P0001', hint = 'already_pending';
  end if;
  if public.config_int('daughter_sons_max_resubmits', 3) > 0
     and (select count(*) from public.admin_requests r
           where r.request_type = 'lineage_request' and r.requester_id = me and r.status = 'rejected')
         > public.config_int('daughter_sons_max_resubmits', 3) then
    raise exception 'وصلتِ حد المحاولات — تواصلي مع الإدارة' using errcode = 'P0001', hint = 'resubmit_limit';
  end if;

  -- الأم: بنت من بنات العائلة (أنثى لها أب ذكر)
  select * into mom from public.women_members where id = p_mother_id;
  if not found or lower(coalesce(mom.gender, '')) <> 'female' or mom.parent_id is null
     or not exists (select 1 from public.women_members f
                     where f.id = mom.parent_id and lower(coalesce(f.gender, 'male')) = 'male') then
    raise exception 'اختاري أمّك من بنات العائلة' using errcode = 'P0001', hint = 'bad_mother';
  end if;
  mname := coalesce(nullif(btrim(mom.full_name), ''), mom.first_name);

  if mom.husband_id is not null then
    select * into h from public.women_members where id = mom.husband_id;
    h_in := exists (select 1 from public.profiles x where x.id = h.id)
            or (h.parent_id is not null and not coalesce(h.is_outside_family, false));
    -- زوج الأم من العائلة ← أبوها في الشجرة: تختاره في «تعديل البيانات» وتربطها الإدارة تحته
    if h_in then
      raise exception 'أبوك من العائلة — اختاريه من الشجرة في «تعديل البيانات»' using errcode = 'P0001', hint = 'father_in_family';
    end if;
  end if;

  if p_father_id is not null then
    if mom.husband_id is distinct from p_father_id then
      raise exception 'هذا ليس زوج أمّك المسجّل' using errcode = 'P0001', hint = 'bad_father';
    end if;
    fname := coalesce(nullif(btrim(h.full_name), ''), h.first_name);
    fdead := coalesce(h.is_deceased, false);
  else
    minw := least(6, greatest(2, public.config_int('daughter_sons_father_min_words', 3)));
    if public.config_bool('daughter_sons_require_grandfather', false) then
      minw := greatest(minw, 4);
    end if;
    if fl = '' or coalesce(array_length(string_to_array(fl, ' '), 1), 0) < minw then
      raise exception 'اكتبي اسم أبيك الكامل' using errcode = '22023', hint = 'name_required';
    end if;
    if length(fl) > 120 then
      raise exception 'الاسم طويل' using errcode = '22023', hint = 'name_too_long';
    end if;
    fname := fl;
    fdead := coalesce(p_father_deceased, false);
  end if;

  -- لأمّها زوج مسجّل وكتبت اسماً: يطابقه؟ (لا يُكتب فوق زوج مختلف — الإدارة تقرّر)
  same := case when mom.husband_id is null then null
               when p_father_id is not null then true
               else private.lineage_names_match(fname, coalesce(nullif(btrim(h.full_name), ''), h.first_name)) end;

  select coalesce(nullif(btrim(p.full_name), ''), p.first_name) into me_name from public.profiles p where p.id = me;
  payload := jsonb_build_object(
    'v', 3,
    'kind', 'daughter_daughter',
    'mother_id', mom.id,
    'mother_name', mname,
    'father_id', p_father_id,
    'father_name', fname,
    'father_is_deceased', fdead,
    'father', case when p_father_id is null then jsonb_build_object(
                'first_name', split_part(fname, ' ', 1), 'full_name', fname, 'is_deceased', fdead) end,
    'mother_husband_id', mom.husband_id,
    'mother_husband_name', case when mom.husband_id is not null
                                then coalesce(nullif(btrim(h.full_name), ''), h.first_name) end,
    'husband_conflict', coalesce(not same, false),
    'summary', 'نسب ' || coalesce(me_name, '') || ': أمّها ' || mname || ' · أبوها ' || fname);

  perform set_config('app.lineage_rpc', 'on', true);
  insert into public.admin_requests (member_id, requester_id, request_type, status, details, new_value)
  values (me, me, 'lineage_request', 'pending', payload::text, mom.id::text)
  returning id into rid;
  perform set_config('app.lineage_rpc', '', true);

  insert into public.notifications (target_member_id, title, body, kind, created_by)
  select s.id, 'طلب نسب جديد', coalesce(me_name, 'عضوة') || ' اختارت أمّها وأبوها — بانتظار التأكيد', 'admin', me
    from public.profiles s
   where s.role in ('owner', 'admin', 'monitor') and s.status = 'active' and s.id <> me;

  return rid;
end;
$function$;

-- ── ٧) قرار الإدارة: فرع «بنت بنت» + عقدة الابن بمعرّف ملفه ──
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

-- ── ٨) المزامنة لا تحذف عقدة صاحب الحساب (عقدة بمعرّف ملفه مربوطة به) ──
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
  elsif exists (select 1 from public.women_members w where w.id = new.id and w.linked_user_id = new.id) then
    -- عقدة صاحب الحساب في شجرة النساء («ابن بنت» / «بنت بنت»، 20261127150000): مكانها هناك لا في شجرة الرجال —
    -- لا حذف، ولا إخفاء (إخفاؤه من شجرة الرجال لا يخصّها)، ولا اسم (اسمها فيه أبوها). الوفاة فقط.
    update public.women_members set
      is_deceased = coalesce(new.is_deceased, false),
      death_date  = new.death_date
    where id = new.id
      and (is_deceased is distinct from coalesce(new.is_deceased, false) or death_date is distinct from new.death_date);
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

-- ── الصلاحيات ──
revoke all on function public.my_daughter_lineage_status() from public, anon;
revoke all on function public.submit_daughter_daughter_lineage(uuid, text, boolean, uuid) from public, anon;
grant execute on function public.my_daughter_lineage_status() to authenticated;
grant execute on function public.submit_daughter_daughter_lineage(uuid, text, boolean, uuid) to authenticated;
