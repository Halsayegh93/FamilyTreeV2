-- تراجع 20261108090000_daughter_sons_restricted («أكمل حسابك»: القفل، البحث بلا تصفّح، «ما لقيت أمي؟»).
-- يُرجع الإرسال والقرار كما في 20261107120000 (والإشعارات بنص «نسبك»). العقد التي أُنشئت («أم جديدة» وأزواج وأبناء)
-- تبقى كما هي (حماية روابط العائلة). طلبات lineage_request المعلّقة بصيغة v2 («أم جديدة» أو «اسم الأب الكامل» سطراً
-- واحداً) لا يقرؤها القرار القديم — عالجها أو ارفضها قبل التراجع. يُرجَع قبل تراجع 20261107120000.
begin;

drop policy if exists diwaniyas_lineage_locked on public.diwaniyas;
drop policy if exists projects_lineage_locked on public.projects;
drop policy if exists family_archive_lineage_locked on public.family_archive;
drop policy if exists women_members_lineage_locked on public.women_members;
drop function if exists public.lineage_locked(text);
drop function if exists public.search_daughters_for_lineage(text);
drop function if exists public.search_men_for_lineage(text);
drop function if exists private.lineage_require_open();
drop function if exists private.lineage_chain_rank(text[], text);
drop function if exists private.lineage_name_words(text);

drop function if exists public.submit_daughter_son_lineage(uuid, uuid, text, text, text, text, boolean, text, text, uuid, boolean);
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

do $mig$
declare d text := pg_get_functiondef('public.approve_join_as_daughter_son(uuid)'::regprocedure); n text;
begin
  n := replace(d, $x$private.daughter_sons_text('notify_join_body', 'تم قبول طلب انضمامك — افتح التطبيق واضغط «أكمل حسابك»: اختر أمّك واكتب اسم أبوك')$x$,
                  $x$'تم قبول طلب انضمامك — افتح التطبيق واختر أمّك واكتب اسم أبوك ليكتمل نسبك'$x$);
  if n = d then raise exception 'approve_join_as_daughter_son: النص المتوقَّع غير موجود'; end if;
  execute n;
end $mig$;
drop function if exists private.daughter_sons_text(text, text);

revoke all on function public.submit_daughter_son_lineage(uuid, uuid, text, text, text, text, boolean) from public, anon;
grant execute on function public.submit_daughter_son_lineage(uuid, uuid, text, text, text, text, boolean) to authenticated;

delete from public.app_config
 where key in ('daughter_sons_locked_sections', 'daughter_sons_mother_min_parts', 'daughter_sons_father_min_words');
update public.app_config
   set label_ar = replace(label_ar, '«أكمل حسابك»', '«نسبك»'),
       help_ar  = replace(replace(replace(help_ar, 'يكمل حسابه', 'يكمل نسبه'),
                                  'قبل إرسال «أكمل حسابك»', 'قبل إرسال نسبه'),
                          '«اسم الأب الكامل» أربع كلمات على الأقل (وإلا «أقل عدد كلمات في اسم الأب الكامل»).',
                          '«أبوي مو موجود» يطلب اسم الجد أيضاً. اسم الأب الأول واسم أبيه واسم العائلة إلزامية دائماً.')
 where key in ('daughter_sons_enabled', 'daughter_sons_allow_later', 'daughter_sons_require_grandfather');
update public.app_config
   set help_ar = 'نصوص تحل محل نصوص التطبيق (الفارغ = نص التطبيق): option_title، option_subtitle، intro_title، intro_body، page_title، page_subtitle، mother_title، father_title، no_father_title، no_father_subtitle، father_name_title، pending_note، rejected_title، outside_tag، son_tag، inbox_title، outside_husband_title.'
 where key = 'daughter_sons_texts';

commit;
