-- «أبناء البنات من خارج العائلة» (موافقة المالك ٢٠٢٦-١١-٠٧، العيّنة samples/daughters-sons/v4.html)
-- APPLIED 2026-11-07 بموافقة المالك. التطبيق يعمل قبله كما هو (الخيارات الجديدة تختفي إن غابت الدوال/العمود).
--
-- المسار:
--  ١) شخص من خارج الشجرة يسجّل عادي ← طلب انضمام (كما هو).
--  ٢) الإدارة تختار «ابن بنت من خارج العائلة» بدل «ربط بالشجرة»: approve_join_as_daughter_son(p_member_id)
--     ← الحساب عضو مفعّل، مخفي من شجرة الرجال (مكانه شجرة النساء)، ويُسجَّل في daughter_son_lineage «بانتظار النسب».
--  ٣) العضو يفتح التطبيق ← صفحة «نسبك»: أمّه من بنات العائلة، وأبوه = زوجها المسجّل أو «أبوي مو موجود» (الاسم الرباعي + متوفى؟)
--     ← submit_daughter_son_lineage(...) يُنشئ طلب admin_requests من نوع lineage_request (الحارس يقبله من هذه الدالة فقط).
--  ٤) الإدارة تقرّر في «الوارد»: decide_lineage_request(p_request_id, 'approve'|'reject', p_reason)
--     القبول: زوج جديد من خارج العائلة (عقدة ذكر بلا أب، is_outside_family، زوج الأم husband_id) إن لم يكن مسجّلاً،
--     ثم عقدة الابن (parent_id = الزوج، mother_id = الأم، linked_user_id = حسابه). الرفض: يبقى «بانتظار النسب» ويرسل من جديد.
--  ٥) الإدارة في شجرة النساء: add_outside_husband(p_woman_id, p_name, p_deceased) — «زوج من خارج العائلة» لبنت بلا زوج،
--     وتُضاف عيالها تحته بمسار «الأبناء» الحالي (إدراج women_members المباشر).
--
-- الهوية من current_profile_id()/current_user_role() فقط. لا فكّ لأي رابط عائلي (الحالات المتعارضة تُرفض بـ hint).
-- عقدة الابن بمعرّف جديد (لا بمعرّف حسابه): sync_profile_update_to_women يحذف عقدة بمعرّف ملف بلا أب ولا تابعين.
-- التراجع: rollback/20261107120000_daughter_sons_lineage_rollback.sql
-- تجربة: cd supabase/tests/family_links && node daughter_sons_lineage.test.mjs

-- ── ٠) الإعدادات على السيرفر (قاعدة المالك: كل ما يتعدّل بلا بناء تطبيق) — app_config()، والتطبيق بافتراضيات مطابقة ──
insert into public.app_config (key, value, default_value, kind, category, label_ar, help_ar, is_public, sort, min_value, max_value)
values
  ('daughter_sons_enabled', 'true'::jsonb, 'true'::jsonb, 'bool', 'tree',
   'أبناء البنات من خارج العائلة',
   'مفعّل: عند قبول طلب الانضمام يظهر خيار «ابن بنت من خارج العائلة»، وفي تفاصيل البنت «زوج من خارج العائلة». مطفأ: يختفيان (ومن قُبل قبلها يكمل نسبه).',
   false, 66, null, null),
  ('daughter_sons_max_resubmits', '3'::jsonb, '3'::jsonb, 'int', 'tree',
   'مرات إعادة إرسال النسب بعد الرفض',
   'كم مرة يعيد العضو إرسال أمّه وأبوه بعد رفض الإدارة. ٠ = بلا حد.',
   false, 67, 0, 20),
  ('daughter_sons_require_grandfather', 'false'::jsonb, 'false'::jsonb, 'bool', 'tree',
   'اسم الجد إلزامي في «نسبك»',
   'مفعّل: «أبوي مو موجود» يطلب اسم الجد أيضاً. اسم الأب الأول واسم أبيه واسم العائلة إلزامية دائماً.',
   false, 68, null, null),
  ('daughter_sons_allow_later', 'true'::jsonb, 'true'::jsonb, 'bool', 'tree',
   'زر «لاحقاً» في صفحة «نسبك»',
   'مفعّل: يقدر العضو يؤجّل الصفحة لين يفتح التطبيق مرة ثانية. مطفأ: لا يدخل التطبيق قبل إرسال نسبه.',
   false, 69, null, null),
  ('daughter_sons_texts', '{}'::jsonb, '{}'::jsonb, 'json', 'tree',
   'نصوص «أبناء البنات»',
   'نصوص تحل محل نصوص التطبيق (الفارغ = نص التطبيق): option_title، option_subtitle، intro_title، intro_body، page_title، page_subtitle، mother_title، father_title، no_father_title، no_father_subtitle، father_name_title، pending_note، rejected_title، outside_tag، son_tag، inbox_title، outside_husband_title.',
   false, 70, null, null)
on conflict (key) do nothing;

-- ── ١) زوج البنت من خارج العائلة ──
alter table public.women_members
  add column if not exists is_outside_family boolean not null default false;

comment on column public.women_members.is_outside_family is
  'Husband of a family daughter who is not from the family (no parent in the tree). Drawn under his wife in the women tree.';

-- ── ٢) «بانتظار النسب» ──
create table if not exists public.daughter_son_lineage (
  profile_id     uuid primary key references public.profiles(id) on delete cascade,
  approved_by    uuid references public.profiles(id) on delete set null,
  approved_at    timestamptz not null default now(),
  women_node_id  uuid,
  completed_at   timestamptz
);
comment on table public.daughter_son_lineage is
  'Accounts approved as «ابن بنت من خارج العائلة». completed_at null = must pick mother + father («نسبك»). Writes via SECURITY DEFINER functions only.';

alter table public.daughter_son_lineage enable row level security;
drop policy if exists daughter_son_lineage_select on public.daughter_son_lineage;
create policy daughter_son_lineage_select on public.daughter_son_lineage for select to authenticated
  using (profile_id = public.current_profile_id()
         or public.current_user_role() = any (array['owner', 'admin', 'monitor']));
revoke all on public.daughter_son_lineage from anon;
revoke insert, update, delete, truncate on public.daughter_son_lineage from authenticated;
grant select on public.daughter_son_lineage to authenticated;

-- ── ٣) نوع الطلب: الاسم العربي، خارج مسار الموافقات (قرار واحد من الإدارة)، والحارس ──
create or replace function public.workflow_specialist_role(p_type text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case
    when p_type in ('news_report', 'content_report') then 'supervisor'
    when p_type in ('contact_message', 'lineage_request') then null
    else 'monitor'
  end;
$function$;

do $mig$
declare d text := pg_get_functiondef('public.admin_request_label(text)'::regprocedure); n text;
begin
  n := replace(d, $x$    when 'relative_add'     then 'طلب إضافة قريبة'$x$,
                  $x$    when 'relative_add'     then 'طلب إضافة قريبة'
    when 'lineage_request'  then 'طلب النسب'$x$);
  if n = d then raise exception 'admin_request_label: نص الحي تغيّر — راجع الترحيل'; end if;
  execute n;
end $mig$;

do $mig$
declare d text := pg_get_functiondef('public.guard_admin_request_insert()'::regprocedure); n text;
begin
  n := replace(d, $x$'account_delete','privacy_request','relative_add') then$x$,
                  $x$'account_delete','privacy_request','relative_add','lineage_request') then$x$);
  n := replace(n, E'  if new.requester_id is null\n',
                  E'  -- «طلب النسب» تُنشئه submit_daughter_son_lineage فقط (20261107120000)\n'
               || E'  if new.request_type = ''lineage_request'' and coalesce(current_setting(''app.lineage_rpc'', true), '''') <> ''on'' then\n'
               || E'    raise exception ''admin_request_type_not_allowed'' using errcode = ''42501'';\n'
               || E'  end if;\n'
               || E'  if new.requester_id is null\n');
  if n = d or length(n) - length(d) < 250 then
    raise exception 'guard_admin_request_insert: نص الحي تغيّر — راجع الترحيل';
  end if;
  execute n;
end $mig$;

-- ── ٤) الإدارة: قبول طلب الانضمام كـ «ابن بنت من خارج العائلة» ──
create or replace function public.approve_join_as_daughter_son(p_member_id uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  me   uuid := public.current_profile_id();
  p    public.profiles%rowtype;
  n    int;
begin
  if coalesce(public.current_user_role(), '') not in ('owner', 'admin', 'monitor') then
    raise exception 'قبول الانضمام للمالك والمدير والمراقب' using errcode = '42501', hint = 'not_allowed';
  end if;
  if not public.config_bool('daughter_sons_enabled', true) then
    raise exception 'الخيار مطفأ من الإعدادات' using errcode = 'P0001', hint = 'feature_off';
  end if;
  select * into p from public.profiles where id = p_member_id for update;
  if not found then
    raise exception 'الحساب غير موجود' using errcode = 'P0001', hint = 'request_not_found';
  end if;
  if lower(coalesce(p.gender, 'male')) = 'female' then
    raise exception 'صاحبة الطلب أنثى — تُربط بشجرة النساء' using errcode = 'P0001', hint = 'not_male';
  end if;
  if p.father_id is not null or exists (select 1 from public.profiles c where c.father_id = p.id) then
    raise exception 'الحساب مربوط بشجرة الرجال — استعمل «ربط بالشجرة»' using errcode = 'P0001', hint = 'has_father';
  end if;
  if exists (select 1 from public.women_members w where w.linked_user_id = p.id) then
    raise exception 'الحساب مربوط بشجرة النساء من قبل' using errcode = 'P0001', hint = 'already_linked';
  end if;
  if coalesce(p.role, '') in ('owner', 'admin', 'monitor', 'supervisor') then
    raise exception 'حساب أحد الإدارة' using errcode = 'P0001', hint = 'staff_account';
  end if;
  -- طلب انضمام/ربط معلّق، أو حساب ما زال «معلّقاً»
  select count(*) into n from public.admin_requests r
   where r.member_id = p.id and r.request_type in ('join_request', 'link_request') and r.status = 'pending';
  if n = 0 and coalesce(p.role, 'pending') <> 'pending' and coalesce(p.status, 'pending') <> 'pending' then
    raise exception 'الطلب عولج من قبل' using errcode = 'P0001', hint = 'already_handled';
  end if;
  if coalesce(p.status, '') in ('frozen', 'deleted') then
    raise exception 'الحساب موقوف' using errcode = 'P0001', hint = 'account_frozen';
  end if;

  update public.profiles
     set role = case when coalesce(role, 'pending') = 'pending' then 'member' else role end,
         status = 'active',
         is_hidden_from_tree = true
   where id = p.id;

  insert into public.daughter_son_lineage (profile_id, approved_by)
  values (p.id, me)
  on conflict (profile_id) do update set approved_by = excluded.approved_by, approved_at = now(), completed_at = null;

  update public.admin_requests
     set status = 'approved', replied_by = me, replied_at = now()
   where member_id = p.id and request_type in ('join_request', 'link_request') and status = 'pending';

  insert into public.notifications (target_member_id, title, body, kind, created_by)
  values (p.id, 'مرحباً بك في العائلة',
          'تم قبول طلب انضمامك — افتح التطبيق واختر أمّك واكتب اسم أبوك ليكتمل نسبك', 'join_approved', me);

  return jsonb_build_object('ok', true, 'member_id', p.id, 'closed_requests', n);
end;
$function$;

-- ── ٥) العضو: حالة النسب ──
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

-- ── ٦) العضو: إرسال اختياره (أمّه + أبوه) للإدارة ──
create or replace function public.submit_daughter_son_lineage(
  p_mother_id uuid,
  p_father_id uuid default null,
  p_first_name text default null,
  p_father_name text default null,
  p_grandfather_name text default null,
  p_family_name text default null,
  p_father_deceased boolean default false)
 returns uuid
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  me     uuid := public.current_profile_id();
  l      public.daughter_son_lineage%rowtype;
  mom    public.women_members%rowtype;
  dad    public.women_members%rowtype;
  fam    public.women_members%rowtype;
  f1     text := btrim(coalesce(p_first_name, ''));
  f2     text := btrim(coalesce(p_father_name, ''));
  f3     text := btrim(coalesce(p_grandfather_name, ''));
  f4     text := btrim(coalesce(p_family_name, ''));
  fname  text;
  me_name text;
  payload jsonb;
  rid    uuid;
begin
  if me is null or not public.is_approved_member() then
    raise exception 'للأعضاء المفعّلين' using errcode = '42501', hint = 'not_allowed';
  end if;
  select * into l from public.daughter_son_lineage where profile_id = me for update;
  if not found or l.completed_at is not null then
    raise exception 'نسبك مكتمل' using errcode = 'P0001', hint = 'not_needed';
  end if;
  if exists (select 1 from public.admin_requests r
              where r.request_type = 'lineage_request' and r.requester_id = me and r.status = 'pending') then
    raise exception 'طلبك عند الإدارة' using errcode = 'P0001', hint = 'already_pending';
  end if;
  -- حدّ إعادة الإرسال بعد الرفض (٠ = بلا حد)
  if public.config_int('daughter_sons_max_resubmits', 3) > 0
     and (select count(*) from public.admin_requests r
           where r.request_type = 'lineage_request' and r.requester_id = me and r.status = 'rejected'
             and r.created_at >= l.approved_at) > public.config_int('daughter_sons_max_resubmits', 3) then
    raise exception 'وصلت حد المحاولات — تواصل مع الإدارة' using errcode = 'P0001', hint = 'resubmit_limit';
  end if;

  -- الأم: بنت من بنات العائلة في شجرة النساء (أنثى لها أب ذكر)
  select * into mom from public.women_members where id = p_mother_id;
  if not found or lower(coalesce(mom.gender, '')) <> 'female' or mom.parent_id is null
     or not exists (select 1 from public.women_members f
                     where f.id = mom.parent_id and lower(coalesce(f.gender, 'male')) = 'male') then
    raise exception 'اختر أمّك من بنات العائلة' using errcode = 'P0001', hint = 'bad_mother';
  end if;

  if p_father_id is not null then
    if mom.husband_id is distinct from p_father_id then
      raise exception 'هذا ليس زوج أمّك المسجّل' using errcode = 'P0001', hint = 'bad_father';
    end if;
    select * into dad from public.women_members where id = p_father_id;
    -- زوجها من العائلة (له ملف في الشجرة) → مكان ابنه شجرة الرجال
    if exists (select 1 from public.profiles x where x.id = p_father_id) or dad.parent_id is not null then
      raise exception 'أبوك من العائلة — اطلب «ربط بالشجرة» من الإدارة' using errcode = 'P0001', hint = 'father_in_family';
    end if;
    fname := coalesce(nullif(btrim(dad.full_name), ''), dad.first_name);
  else
    if mom.husband_id is not null then
      raise exception 'لأمّك زوج مسجّل — اختره' using errcode = 'P0001', hint = 'mother_has_husband';
    end if;
    if f1 = '' or f2 = '' or f4 = ''
       or (f3 = '' and public.config_bool('daughter_sons_require_grandfather', false)) then
      raise exception 'اكتب اسم أبوك واسم أبيه واسم العائلة' using errcode = '22023', hint = 'name_required';
    end if;
    if greatest(length(f1), length(f2), length(f3), length(f4)) > 40 then
      raise exception 'الاسم طويل' using errcode = '22023', hint = 'name_too_long';
    end if;
    fname := btrim(regexp_replace(concat_ws(' ', f1, f2, nullif(f3, ''), f4), '\s+', ' ', 'g'));
  end if;

  select coalesce(nullif(btrim(p.full_name), ''), p.first_name) into me_name from public.profiles p where p.id = me;
  payload := jsonb_build_object(
    'v', 1,
    'mother_id', mom.id,
    'mother_name', coalesce(nullif(btrim(mom.full_name), ''), mom.first_name),
    'father_id', p_father_id,
    'father_name', fname,
    'father', case when p_father_id is null then jsonb_build_object(
                'first_name', f1, 'father_name', f2, 'grandfather_name', nullif(f3, ''), 'family_name', f4,
                'is_deceased', coalesce(p_father_deceased, false)) end,
    'summary', 'نسب ' || coalesce(me_name, '') || ': أمّه ' || coalesce(nullif(btrim(mom.full_name), ''), mom.first_name)
               || ' · أبوه ' || fname);

  perform set_config('app.lineage_rpc', 'on', true);
  insert into public.admin_requests (member_id, requester_id, request_type, status, details, new_value)
  values (me, me, 'lineage_request', 'pending', payload::text, mom.id::text)
  returning id into rid;
  perform set_config('app.lineage_rpc', '', true);

  -- يصل الإدارة (المالك/المدير/المراقب) — الدفع يتبع جدول الإشعارات
  insert into public.notifications (target_member_id, title, body, kind, created_by)
  select s.id, 'طلب نسب جديد', coalesce(me_name, 'عضو') || ' اختار أمّه وأبوه — بانتظار التأكيد', 'admin', me
    from public.profiles s
   where s.role in ('owner', 'admin', 'monitor') and s.status = 'active' and s.id <> me;

  return rid;
end;
$function$;

-- ── ٧) الإدارة: قبول/رفض طلب النسب ──
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
  l        public.daughter_son_lineage%rowtype;
  son      public.profiles%rowtype;
  mom      public.women_members%rowtype;
  hid      uuid;
  hname    text;
  son_id   uuid;
  son_first text;
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
    values (r.requester_id, 'لم يتم تأكيد نسبك',
            'راجع اختيار أمّك وأبوك وأرسله من جديد' || coalesce(E'\nالسبب: ' || reason, ''), 'request_rejected', me);
    return jsonb_build_object('ok', true, 'request_id', r.id, 'status', 'rejected');
  end if;

  begin
    d := r.details::jsonb;
  exception when others then
    d := null;
  end;
  if d is null or jsonb_typeof(d) <> 'object' or coalesce(d->>'mother_id', '') = '' then
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

  select * into mom from public.women_members where id = (d->>'mother_id')::uuid for update;
  if not found or lower(coalesce(mom.gender, '')) <> 'female' or mom.parent_id is null then
    raise exception 'الأم لم تعد في شجرة النساء' using errcode = 'P0001', hint = 'bad_mother';
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
  values (son.id, 'تم تأكيد نسبك', 'صرت في شجرة النساء تحت أمّك ' || coalesce(nullif(btrim(mom.first_name), ''), '')
          || ' وأبوك ' || hname, 'admin', me);

  return jsonb_build_object('ok', true, 'request_id', r.id, 'status', 'approved',
                            'husband_id', hid, 'son_node_id', son_id);
end;
$function$;

-- ── ٨) الإدارة في شجرة النساء: «زوج من خارج العائلة» لبنت بلا زوج ──
create or replace function public.add_outside_husband(p_woman_id uuid, p_name text, p_deceased boolean default false)
 returns uuid
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  w   public.women_members%rowtype;
  nm  text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  hid uuid;
begin
  if coalesce(public.current_user_role(), '') not in ('owner', 'admin', 'monitor') then
    raise exception 'للمالك والمدير والمراقب' using errcode = '42501', hint = 'not_allowed';
  end if;
  if not public.config_bool('daughter_sons_enabled', true) then
    raise exception 'الخيار مطفأ من الإعدادات' using errcode = 'P0001', hint = 'feature_off';
  end if;
  select * into w from public.women_members where id = p_woman_id for update;
  if not found or lower(coalesce(w.gender, '')) <> 'female' then
    raise exception 'ليست أنثى في شجرة النساء' using errcode = 'P0001', hint = 'not_female_node';
  end if;
  if w.husband_id is not null then
    raise exception 'لها زوج مسجّل' using errcode = 'P0001', hint = 'has_husband';
  end if;
  if nm = '' then
    raise exception 'اكتب اسم الزوج' using errcode = '22023', hint = 'name_required';
  end if;
  if length(nm) > 120 then
    raise exception 'الاسم طويل' using errcode = '22023', hint = 'name_too_long';
  end if;
  insert into public.women_members (id, first_name, full_name, gender, parent_id, is_married, is_deceased,
                                    is_outside_family, sort_order)
  values (gen_random_uuid(), split_part(nm, ' ', 1), nm, 'male', null, true, coalesce(p_deceased, false), true, 0)
  returning id into hid;
  update public.women_members set husband_id = hid, is_married = true where id = w.id;
  return hid;
end;
$function$;

-- ── الصلاحيات ──
revoke all on function public.approve_join_as_daughter_son(uuid) from public, anon;
revoke all on function public.my_lineage_status() from public, anon;
revoke all on function public.submit_daughter_son_lineage(uuid, uuid, text, text, text, text, boolean) from public, anon;
revoke all on function public.decide_lineage_request(uuid, text, text) from public, anon;
revoke all on function public.add_outside_husband(uuid, text, boolean) from public, anon;
grant execute on function public.approve_join_as_daughter_son(uuid) to authenticated;
grant execute on function public.my_lineage_status() to authenticated;
grant execute on function public.submit_daughter_son_lineage(uuid, uuid, text, text, text, text, boolean) to authenticated;
grant execute on function public.decide_lineage_request(uuid, text, text) to authenticated;
grant execute on function public.add_outside_husband(uuid, text, boolean) to authenticated;
