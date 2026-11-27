-- «التسجيل من خارج العائلة» ثم «استكمال التسجيل» بعد قبول الانضمام (موافقة المالك ٢٠٢٦-١١-٢٧، الوحدة R1)
-- مطبَّق على الحي ٢٠٢٦-١١-٢٧ بعد تجربة begin…rollback؛ تجربة node ٦٥/٦٥ والسابقة كما هي.
-- NOT APPLIED — يطبّقه المدير بعد تجربة begin…rollback وموافقة المالك. فوق 20261127150000_daughter_daughters (حيّ).
--
-- كلام المالك: «التسجيل من خارج العائلة ابيه بدون اختيار الام يكون بالبداية» + «بعدين يكمل تسجيله بعد ما اوافق عليه».
-- المسار:
--  ١) التسجيل «من خارج العائلة» (التطبيق): الاسم الثلاثي · العائلة (profiles.family_name) · تاريخ الميلاد · الجنس ← طلب انضمام
--     بعلامة `|outside_family:1` في تفاصيله (لا سيرفر جديد هنا — حارس الطلبات يقبل نص التفاصيل كما هو).
--  ٢) الإدارة تقبل الانضمام «من خارج العائلة»: approve_join_as_daughter_son — كان للذكر فقط، الآن للأنثى أيضاً (بنت البنت)
--     ← حساب مفعّل مقيّد في daughter_son_lineage «بانتظار النسب» (القفل نفسه: lineage_locked + daughter_son_women_only).
--  ٣) العضو يفتح التطبيق ← «استكمال التسجيل» (بوابة «أكمل حسابك» نفسها، و«لاحقاً» من daughter_sons_allow_later):
--     أولاً «هل الأم من العائلة؟» نعم/لا (صياغة المالك).
--     «نعم» ← «اسم الوالدة الرباعي» فقط (العائلة «المحمدعلي») ← submit_outside_lineage(p_mother_name) ← lineage_request بنوع
--     outside_typed. اسم الوالد لا يُسأل: يأخذه السيرفر من اسم صاحب الحساب المسجّل (ما بعد الاسم الأول).
--     «لا» ← لا اسم ولا عائلة ولا طلب للإدارة (الانضمام مقبول من قبل): mark_outside_mother() يكتب
--     daughter_son_lineage.limited_at — عضو مفعّل «بصلاحيات محدودة» دائماً (المالك: «اقل من العضو العادي… نحددها بعدين»):
--     الأقسام في app_config.outside_member_locked_sections (افتراضها قائمة القفل الحالية)، lineage_locked يطبّقها في سياسات
--     القراءة، وmy_lineage_status يرجع limited = true فتختفي «استكمال التسجيل». بلا أي كتابة في الشجرة.
--  ٤) «الوارد»: lineage_mother_suggestions(p_request_id) — بنات العائلة المطابقات لاسم الوالدة المكتوب («بنت فلان · زوجة فلان»،
--     ومطابقة زوجها للوالد)، للمالك والمدير والمراقب. المراجع يختار الوالدة ثم يوافق:
--     decide_lineage_request(p_request_id, 'approve', null, p_mother_id) — المعامل الرابع جديد (افتراضه null؛ النسخ القديمة كما هي).
--     الوالد: زوج الوالدة المسجّل يُعاد إن طابق الاسم المشتق (private.lineage_names_match)، زوجها من العائلة ← father_in_family،
--     زوج باسم آخر ← mother_has_other_husband (لا كتابة فوقه)، بلا زوج ← عقدة رجل من خارج العائلة زوجاً لها.
--     عقدته بمعرّف ملفه وبجنس ملفه (البنت أنثى). صفّ daughter_son_lineage يكتمل.
--     إشعار القبول والرفض يصل صاحب الطلب أيّاً كان من قرّر (المالك أو المدير أو المراقب) — كان كذلك، وثُبّت بالتجربة.
--     نصوص الإشعارات رسمية: «الوالد» و«الوالدة» فقط. فرع «بنت بنت» (قيد المراجعة) كما في 20261127150000.
--
--  ٥) بطاقة «بنت بنت» في شاشة الانتظار (lineage_daughter_applicant) لا تظهر لمن سجّل بعد هذه الخطوة (|family_signup:1 /
--     |outside_family:1) — «من العائلة» صار بلا اختيار الوالد (الإدارة تربط)، فالبطاقة احتياط لمن سجّل قبلها فقط.
--
-- الهوية من current_profile_id()/current_user_role() فقط. لا فكّ لأي رابط عائلي.
-- التراجع: rollback/20261127160000_outside_family_signup_rollback.sql
-- تجربة: cd supabase/tests/family_links && node outside_family_signup.test.mjs

-- ── ١) قبول الانضمام «من خارج العائلة»: الذكر والأنثى ──
do $mig$
declare d text := pg_get_functiondef('public.approve_join_as_daughter_son(uuid)'::regprocedure); n text;
begin
  n := replace(d, $x$  if lower(coalesce(p.gender, 'male')) = 'female' then
    raise exception 'صاحبة الطلب أنثى — تُربط بشجرة النساء' using errcode = 'P0001', hint = 'not_male';
  end if;
$x$, $x$  -- الأنثى أيضاً (بنت البنت من خارج العائلة، 20261127160000) — «استكمال التسجيل» بعد القبول
$x$);
  n := replace(n, $x$'تم قبول طلب انضمامك — افتح التطبيق واضغط «أكمل حسابك»: اختر أمّك واكتب اسم أبوك'$x$,
                  $x$'تم قبول طلب انضمامك. يُرجى فتح التطبيق واستكمال التسجيل باختيار الوالدة وكتابة اسم الوالد.'$x$);
  if n = d or position('not_male' in n) > 0 or position('استكمال التسجيل' in n) = 0 then
    raise exception 'approve_join_as_daughter_son: نص الحي تغيّر — راجع الترحيل';
  end if;
  execute n;
end $mig$;

-- ── ١ب) «صلاحيات محدودة» دائمة لمن الوالدة من خارج العائلة (المالك: «يكون اقل من العضو العادي صلاحياته… نحددها بعدين») ──
alter table public.daughter_son_lineage add column if not exists limited_at timestamptz;
comment on column public.daughter_son_lineage.limited_at is
  'Set by mark_outside_mother() («هل الأم من العائلة؟» لا): an active member with permanent limited access (outside_member_locked_sections), not placed in the women tree.';

insert into public.app_config (key, value, default_value, kind, category, label_ar, help_ar, is_public, sort, min_value, max_value)
values
  ('outside_member_locked_sections',
   '["diwaniyas", "projects", "library", "women_tree", "member_details"]'::jsonb,
   '["diwaniyas", "projects", "library", "women_tree", "member_details"]'::jsonb, 'json', 'tree',
   'الأقسام المقفولة على «الصلاحيات المحدودة»',
   'من أجاب «لا» على «هل الأم من العائلة؟»: عضو بصلاحيات أقل من العضو العادي. القائمة: diwaniyas (الديوانيات) · projects (المشاريع) · library (المكتبة) · women_tree (شجرة النساء) · member_details (تفاصيل العضو). [] = لا قفل. السيرفر يمنع قراءة الأربعة الأولى، والتطبيق يقفل الخمسة.',
   false, 75, null, null)
on conflict (key) do nothing;

create or replace function public.lineage_locked(p_section text)
 returns boolean
 language sql
 stable
 security definer
 set search_path to ''
as $function$
  select case
    when coalesce(public.current_user_role(), '') in ('owner', 'admin', 'monitor', 'supervisor') then false
    -- «صلاحيات محدودة» دائمة (الوالدة من خارج العائلة، 20261127160000): outside_member_locked_sections
    when exists (select 1 from public.daughter_son_lineage d
                  where d.profile_id = public.current_profile_id() and d.limited_at is not null)
      then coalesce((select case when jsonb_typeof(c.value) = 'array' then c.value ? p_section end
                       from public.app_config c where c.key = 'outside_member_locked_sections'),
                    p_section = any (array['diwaniyas', 'projects', 'library', 'women_tree', 'member_details']))
    -- «استكمال التسجيل» لم يُعتمد بعد: daughter_sons_locked_sections (كما كان)
    when exists (select 1 from public.daughter_son_lineage d
                  where d.profile_id = public.current_profile_id() and d.completed_at is null)
      then coalesce((select case when jsonb_typeof(c.value) = 'array' then c.value ? p_section end
                       from public.app_config c where c.key = 'daughter_sons_locked_sections'),
                    p_section = any (array['diwaniyas', 'projects', 'library', 'women_tree', 'member_details']))
    else false
  end;
$function$;
comment on function public.lineage_locked(text) is
  'Caller is a daughter''s son/daughter whose «استكمال التسجيل» is not approved yet (daughter_sons_locked_sections), or a limited member (outside_member_locked_sections). Used by RESTRICTIVE select policies.';

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
    'needs', exists (select 1 from l where l.completed_at is null and l.limited_at is null) and not exists (select 1 from pend),
    -- «الوالدة من خارج العائلة» (20261127160000): عضو بصلاحيات محدودة دائماً — لا «استكمال التسجيل»
    'limited', exists (select 1 from l where l.limited_at is not null),
    'pending', exists (select 1 from pend),
    'pending_request_id', (select id from pend),
    'completed', exists (select 1 from l where l.completed_at is not null),
    'rejected_reason', case when exists (select 1 from l where l.completed_at is null and l.limited_at is null)
                            then (select nullif(btrim(coalesce(admin_reply, '')), '') from rej) end,
    'was_rejected', exists (select 1 from l where l.completed_at is null and l.limited_at is null) and exists (select 1 from rej));
$function$;

-- ── ١ج) بطاقة «بنت بنت» في شاشة الانتظار احتياط لمن سجّل قبل هذه الخطوة فقط ──
-- «من العائلة» الجديد بلا اختيار الوالد (|family_signup:1 — الإدارة تربط) و«من خارج العائلة» (|outside_family:1 — «استكمال
-- التسجيل» بعد القبول) لا تظهر لهما البطاقة.
do $mig$
declare d text := pg_get_functiondef('private.lineage_daughter_applicant()'::regprocedure); n text;
begin
  n := replace(d, $x$                   and coalesce(r.details, '') like '%|father_id:%') then$x$,
                  $x$                   and (coalesce(r.details, '') like '%|father_id:%'
                        -- سجّلت بعد 20261127160000: «من العائلة» أو «من خارج العائلة»
                        or coalesce(r.details, '') like '%|family_signup:1%'
                        or coalesce(r.details, '') like '%|outside_family:1%')) then$x$);
  if n = d then raise exception 'lineage_daughter_applicant: نص الحي تغيّر — راجع الترحيل'; end if;
  execute n;
end $mig$;

-- ── ٢) «استكمال التسجيل»: اسم الوالدة مكتوباً + عائلتها، والوالد من اسم صاحب الحساب ──
create or replace function public.submit_outside_lineage(p_mother_name text)
 returns uuid
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  me      uuid := public.current_profile_id();
  l       public.daughter_son_lineage%rowtype;
  p       public.profiles%rowtype;
  mn      text := btrim(regexp_replace(coalesce(p_mother_name, ''), '\s+', ' ', 'g'));
  -- «هل الأم من العائلة؟» نعم ← العائلة «المحمدعلي» ثابتة
  mf      text := 'المحمدعلي';
  w       text[];
  fname   text;
  me_name text;
  payload jsonb;
  rid     uuid;
begin
  if me is null or not public.is_approved_member() then
    raise exception 'للأعضاء المفعّلين' using errcode = '42501', hint = 'not_allowed';
  end if;
  select * into l from public.daughter_son_lineage where profile_id = me for update;
  if not found or l.completed_at is not null or l.limited_at is not null then
    raise exception 'التسجيل مكتمل' using errcode = 'P0001', hint = 'not_needed';
  end if;
  if exists (select 1 from public.admin_requests r
              where r.request_type = 'lineage_request' and r.requester_id = me and r.status = 'pending') then
    raise exception 'الطلب لدى الإدارة' using errcode = 'P0001', hint = 'already_pending';
  end if;
  if public.config_int('daughter_sons_max_resubmits', 3) > 0
     and (select count(*) from public.admin_requests r
           where r.request_type = 'lineage_request' and r.requester_id = me and r.status = 'rejected'
             and r.created_at >= l.approved_at) > public.config_int('daughter_sons_max_resubmits', 3) then
    raise exception 'تم بلوغ الحد الأقصى للمحاولات — يُرجى التواصل مع الإدارة' using errcode = 'P0001', hint = 'resubmit_limit';
  end if;
  if coalesce(array_length(string_to_array(mn, ' '), 1), 0) < 2 then
    raise exception 'يُرجى كتابة اسم الوالدة' using errcode = '22023', hint = 'name_required';
  end if;
  if length(mn) > 120 then
    raise exception 'الاسم طويل' using errcode = '22023', hint = 'name_too_long';
  end if;

  -- الوالد = اسم صاحب الحساب بعد الاسم الأول (الاسم الثلاثي + العائلة عند التسجيل)
  select * into p from public.profiles where id = me;
  me_name := btrim(regexp_replace(coalesce(nullif(btrim(p.full_name), ''), p.first_name, ''), '\s+', ' ', 'g'));
  w := string_to_array(me_name, ' ');
  fname := case when coalesce(array_length(w, 1), 0) >= 2 then array_to_string(w[2:array_length(w, 1)], ' ') else '' end;
  if coalesce(array_length(string_to_array(nullif(fname, ''), ' '), 1), 0) < 2 then
    raise exception 'اسم الوالد غير مكتمل في الملف — يُرجى التواصل مع الإدارة' using errcode = 'P0001', hint = 'father_name_missing';
  end if;

  payload := jsonb_build_object(
    'v', 4,
    'kind', 'outside_typed',
    'mother_id', null,
    'mother_name', mn || ' ' || mf,
    'mother_typed_name', mn,
    'mother_family', mf,
    'father_id', null,
    'father_name', fname,
    'father_is_deceased', false,
    'father', jsonb_build_object('first_name', split_part(fname, ' ', 1), 'full_name', fname, 'is_deceased', false),
    'summary', 'نسب ' || me_name || ': الوالدة ' || mn || ' ' || mf || ' · الوالد ' || fname);

  perform set_config('app.lineage_rpc', 'on', true);
  insert into public.admin_requests (member_id, requester_id, request_type, status, details, new_value)
  values (me, me, 'lineage_request', 'pending', payload::text, null)
  returning id into rid;
  perform set_config('app.lineage_rpc', '', true);

  insert into public.notifications (target_member_id, title, body, kind, created_by)
  select s.id, 'طلب نسب جديد',
         me_name || ' أرسل اسم الوالدة — يُرجى اختيارها من بنات العائلة', 'admin', me
    from public.profiles s
   where s.role in ('owner', 'admin', 'monitor') and s.status = 'active' and s.id <> me;

  return rid;
end;
$function$;

-- «هل الأم من العائلة؟» لا ← عضو «بصلاحيات محدودة» مباشرة، بلا طلب (الانضمام مقبول من قبل)
create or replace function public.mark_outside_mother()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  me uuid := public.current_profile_id();
  l  public.daughter_son_lineage%rowtype;
begin
  if me is null or not public.is_approved_member() then
    raise exception 'للأعضاء المفعّلين' using errcode = '42501', hint = 'not_allowed';
  end if;
  select * into l from public.daughter_son_lineage where profile_id = me for update;
  if not found or l.completed_at is not null or l.limited_at is not null then
    raise exception 'التسجيل مكتمل' using errcode = 'P0001', hint = 'not_needed';
  end if;
  if exists (select 1 from public.admin_requests r
              where r.request_type = 'lineage_request' and r.requester_id = me and r.status = 'pending') then
    raise exception 'الطلب لدى الإدارة' using errcode = 'P0001', hint = 'already_pending';
  end if;
  update public.daughter_son_lineage set limited_at = now() where profile_id = me;
  return jsonb_build_object('ok', true, 'limited', true);
end;
$function$;

-- ── ٣) «الوارد»: بنات العائلة المطابقات لاسم الوالدة المكتوب (أطول بداية مطابقة: ٤ ثم ٣ ثم كلمتان) ──
create or replace function public.lineage_mother_suggestions(p_request_id uuid)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
declare
  r   public.admin_requests%rowtype;
  d   jsonb;
  q   text[];
  fa  text;
  k   int;
  res jsonb;
begin
  if coalesce(public.current_user_role(), '') not in ('owner', 'admin', 'monitor') then
    raise exception 'طلبات النسب للمالك والمدير والمراقب' using errcode = '42501', hint = 'not_allowed';
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
  if d is null or jsonb_typeof(d) <> 'object' then return '[]'::jsonb; end if;
  q := private.lineage_name_words(left(coalesce(d->>'mother_typed_name', d->>'mother_name', ''), 200));
  fa := coalesce(d->>'father_name', '');
  for k in reverse least(coalesce(array_length(q, 1), 0), 4) .. 2 loop
    select coalesce(jsonb_agg(x.o order by x.rank, x.sort_order, x.full_name), '[]'::jsonb) into res
      from (
        select jsonb_build_object(
                 'id', w.id,
                 'first_name', coalesce(w.first_name, ''),
                 'full_name', coalesce(nullif(btrim(w.full_name), ''), w.first_name, ''),
                 'father_name', coalesce(nullif(btrim(f.full_name), ''), f.first_name),
                 'husband_id', w.husband_id,
                 'husband_name', coalesce(nullif(btrim(h.full_name), ''), h.first_name),
                 'husband_in_family', h.id is not null and (
                     exists (select 1 from public.profiles x where x.id = h.id)
                     or (h.parent_id is not null and not coalesce(h.is_outside_family, false))),
                 'husband_matches', h.id is not null
                     and private.lineage_names_match(fa, coalesce(nullif(btrim(h.full_name), ''), h.first_name)),
                 'matched_words', k) as o,
               rk.rank, w.sort_order, w.full_name
          from public.women_members w
          join public.women_members f on f.id = w.parent_id and lower(coalesce(f.gender, 'male')) = 'male'
          left join public.women_members h on h.id = w.husband_id
          cross join lateral (select private.lineage_chain_rank(
                                private.lineage_name_words(coalesce(nullif(btrim(w.full_name), ''), w.first_name)),
                                array_to_string(q[1:k], '')) as rank) rk
         where lower(coalesce(w.gender, '')) = 'female'
           and not coalesce(w.is_web_only, false)
           and rk.rank is not null
         order by rk.rank, w.sort_order, w.full_name
         limit 10) x;
    if jsonb_array_length(res) > 0 then return res; end if;
  end loop;
  return '[]'::jsonb;
end;
$function$;

-- ── ٤) قرار الإدارة (المعامل الرابع p_mother_id لطلب «استكمال التسجيل») ──
drop function if exists public.decide_lineage_request(uuid, text, text);
create or replace function public.decide_lineage_request(p_request_id uuid, p_decision text, p_reason text default null,
                                                         p_mother_id uuid default null)
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
  is_typed boolean := false;
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
  -- «استكمال التسجيل» (20261127160000): اسم الوالدة مكتوباً — المراجع يختارها من بنات العائلة (p_mother_id)
  is_typed := d is not null and jsonb_typeof(d) = 'object' and d->>'kind' = 'outside_typed';

  if decision = 'reject' then
    update public.admin_requests
       set status = 'rejected', admin_reply = reason, replied_by = me, replied_at = now()
     where id = r.id;
    if is_dd then
      -- طلب انضمامها يبقى معلّقاً — ترسل من جديد أو تربطها الإدارة بطريق آخر
      insert into public.notifications (target_member_id, title, body, kind, created_by)
      values (r.requester_id, 'يُرجى مراجعة البيانات وإرسالها من جديد',
              'يُرجى مراجعة اختيار الوالدة واسم الوالد في التطبيق وإرسال الطلب من جديد.' || coalesce(E'\nالسبب: ' || reason, ''),
              'request_rejected', me);
    else
      insert into public.notifications (target_member_id, title, body, kind, created_by)
      values (r.requester_id,
              private.daughter_sons_text('notify_rejected_title', 'يُرجى مراجعة البيانات وإرسالها من جديد'),
              private.daughter_sons_text('notify_rejected_body', 'يُرجى فتح «استكمال التسجيل» ومراجعة اختيار الوالدة والوالد.')
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

  -- ═══ «ابن بنت» / «بنت بنت» المقبول من قبل — «استكمال التسجيل» (20261108090000؛ 20261127160000: الجنس من ملفه، وزوج الوالدة المسجّل) ═══
  if is_typed then
    if p_mother_id is null then
      raise exception 'يُرجى اختيار الوالدة من بنات العائلة قبل الموافقة' using errcode = 'P0001', hint = 'mother_required';
    end if;
    d := d || jsonb_build_object('mother_id', p_mother_id);
  elsif p_mother_id is not null and p_mother_id is distinct from nullif(d->>'mother_id', '')::uuid then
    raise exception 'الوالدة محدّدة في الطلب' using errcode = '22023', hint = 'bad_payload';
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
  elsif mom.husband_id is not null then
    -- كتب اسماً وللوالدة زوج مسجّل (أجاب «لا» على «هل هو الوالد؟»، أو تزوّجت بعد الطلب): يُعاد زوجها إن تطابق الاسم
    -- (lineage_names_match)، وإلا لا كتابة فوقه — الإدارة تصحّح الشجرة أو ترفض
    select * into hus from public.women_members where id = mom.husband_id;
    if exists (select 1 from public.profiles x where x.id = hus.id) then
      raise exception 'الأب من العائلة — «ربط بالشجرة»' using errcode = 'P0001', hint = 'father_in_family';
    end if;
    if not private.lineage_names_match(btrim(coalesce(d->>'father_name', '')),
                                       coalesce(nullif(btrim(hus.full_name), ''), hus.first_name)) then
      raise exception 'للأم زوج مسجّل باسم آخر (%) — صحّح الشجرة يدوياً أو ارفض الطلب',
            coalesce(nullif(btrim(hus.full_name), ''), hus.first_name)
        using errcode = 'P0001', hint = 'mother_has_other_husband';
    end if;
    hid := hus.id;
    hname := coalesce(nullif(btrim(hus.full_name), ''), hus.first_name);
  else
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
  values (son.id, son_first, btrim(son_first || ' ' || hname),
          case when lower(coalesce(son.gender, 'male')) = 'female' then 'female' else 'male' end,
          hid, mom.id, son.id, false,
          coalesce((select max(c.sort_order) + 1 from public.women_members c where c.parent_id = hid), 0))
  returning id into son_id;

  update public.daughter_son_lineage set completed_at = now(), women_node_id = son_id where profile_id = son.id;
  update public.admin_requests set status = 'approved', replied_by = me, replied_at = now() where id = r.id;

  -- يصل صاحب الطلب أيّاً كان من قرّر (المالك أو المدير أو المراقب)
  insert into public.notifications (target_member_id, title, body, kind, created_by)
  values (son.id, private.daughter_sons_text('notify_completed_title', 'اكتمل التسجيل'),
          'تمت إضافتك إلى شجرة النساء تحت الوالدة ' || coalesce(nullif(btrim(mom.first_name), ''), '')
          || ' والوالد ' || hname, 'admin', me);

  return jsonb_build_object('ok', true, 'request_id', r.id, 'status', 'approved',
                            'mother_id', mom.id, 'new_mother', new_mom,
                            'husband_id', hid, 'son_node_id', son_id);
end;
$function$;

-- ── الصلاحيات ──
revoke all on function public.submit_outside_lineage(text) from public, anon;
grant execute on function public.submit_outside_lineage(text) to authenticated;
revoke all on function public.mark_outside_mother() from public, anon;
grant execute on function public.mark_outside_mother() to authenticated;
revoke all on function public.lineage_mother_suggestions(uuid) from public, anon;
grant execute on function public.lineage_mother_suggestions(uuid) to authenticated;
revoke all on function public.decide_lineage_request(uuid, text, text, uuid) from public, anon;
grant execute on function public.decide_lineage_request(uuid, text, text, uuid) to authenticated;
