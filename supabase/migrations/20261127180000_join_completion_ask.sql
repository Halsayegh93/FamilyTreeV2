-- «طلب استكمال البيانات» من مربّعات «الوارد» (المالك ٢٠٢٦-١١-٢٧: «اذا البيانات ناقصة نقدر نرسلها حق العضو ان البيانات هذي
-- مطبَّق على الحي ٢٠٢٦-١١-٢٧ بعد تجربة begin…rollback.
-- ناقصة»، الوحدة R2). مسار «طلب معلومات» الموجود (advance_admin_request 'request_info') لا يصلح هنا: يشترط تشغيل مسار
-- الموافقات (مطفأ)، وحقوله phone/birth_date/death_date/full_name/text فقط، والرد لصاحب طلب في المسار — فهذه دوال صغيرة مستقلة:
--
--  ask_join_completion(p_request_id, p_fields text[], p_note text) → معرّف الطلب
--    • للمالك والمدير والمراقب (نفس link_woman_account و decide_lineage_request)، والطلب معلّق:
--      طلب انضمام/ربط ← الحقول من: full_name · birth_date · gender · family · photo
--      طلب نسب («استكمال التسجيل») ← mother_name
--    • الطلب يبقى «معلّقاً» كما هو (الحساب معلّق، أو محدود في «استكمال التسجيل»)؛ يُسجَّل الطلب في join_completion_asks
--      (طلب مفتوح واحد لكل طلب — الجديد يحلّ محلّ القديم) ويصل العضو إشعار رسمي «يُرجى استكمال البيانات: …».
--  my_completion_ask() → {request_id, kind 'join'|'lineage', fields, note, asked_at} أو null — لصاحب الطلب نفسه.
--  answer_completion_ask(p_values jsonb) — صاحب الطلب بعد الإرسال من جديد:
--      الانضمام: البيانات تُحفظ في ملفه من مربّع التسجيل نفسه (كما «تعديل الطلب»)، والدالة تتحقق أن المطلوب موجود في ملفه
--      ثم تغلق الطلب المفتوح. النسب: {"mother_name": "…"} (كلمتان على الأقل، ١٢٠ حرفاً) يُكتب في تفاصيل طلب النسب المعلّق
--      نفسه (submit_outside_lineage يرفض طلباً ثانياً ما دام الأول معلّقاً). وتُبلَّغ الإدارة «تم استكمال البيانات».
-- أخطاء بـ hint: not_allowed · request_not_found · already_handled · bad_field · fields_required · note_too_long ·
--   no_ask · missing_value · name_required · name_too_long
-- NOT APPLIED — يطبّقه المدير بعد تجربة begin…rollback وموافقة المالك.
-- التراجع: rollback/20261127180000_join_completion_ask_rollback.sql
-- تجربة: cd supabase/tests/family_links && node join_completion_ask.test.mjs

create table if not exists public.join_completion_asks (
  id          uuid primary key default gen_random_uuid(),
  request_id  uuid not null references public.admin_requests(id) on delete cascade,
  member_id   uuid not null references public.profiles(id) on delete cascade,
  fields      text[] not null,
  note        text,
  asked_by    uuid references public.profiles(id) on delete set null,
  asked_at    timestamptz not null default now(),
  answered_at timestamptz
);
create index if not exists join_completion_asks_member_open
  on public.join_completion_asks (member_id) where answered_at is null;
alter table public.join_completion_asks enable row level security;
-- لا سياسات: القراءة والكتابة عبر الدوال فقط
revoke all on public.join_completion_asks from public, anon, authenticated;

create or replace function public.join_completion_field_label(p_field text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select case p_field
    when 'full_name'   then 'الاسم الرباعي'
    when 'birth_date'  then 'تاريخ الميلاد'
    when 'gender'      then 'الجنس'
    when 'family'      then 'العائلة'
    when 'photo'       then 'الصورة الشخصية'
    when 'mother_name' then 'اسم الوالدة'
    else p_field end;
$function$;

create or replace function public.ask_join_completion(p_request_id uuid, p_fields text[], p_note text default null)
 returns uuid
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  me      uuid := public.current_profile_id();
  r       public.admin_requests%rowtype;
  allowed text[];
  fields  text[];
  f       text;
  note    text := nullif(btrim(regexp_replace(coalesce(p_note, ''), '\s+', ' ', 'g')), '');
  items   text;
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
  allowed := case when r.request_type = 'lineage_request' then array['mother_name']
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
$function$;

create or replace function public.my_completion_ask()
 returns jsonb
 language sql
 stable
 security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object(
           'request_id', a.request_id,
           'kind', case when r.request_type = 'lineage_request' then 'lineage' else 'join' end,
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
$function$;

create or replace function public.answer_completion_ask(p_values jsonb default '{}'::jsonb)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  me    uuid := public.current_profile_id();
  a     public.join_completion_asks%rowtype;
  r     public.admin_requests%rowtype;
  p     public.profiles%rowtype;
  f     text;
  mn    text;
  d     jsonb;
  who   text;
begin
  if me is null then
    raise exception 'سجّل الدخول أولاً' using errcode = '42501', hint = 'not_allowed';
  end if;
  select a2.* into a from public.join_completion_asks a2
    join public.admin_requests r2 on r2.id = a2.request_id
   where a2.member_id = me and a2.answered_at is null and r2.status = 'pending'
   order by a2.asked_at desc limit 1
   for update of a2;
  if not found then
    raise exception 'لا يوجد طلب استكمال مفتوح' using errcode = 'P0001', hint = 'no_ask';
  end if;
  select * into r from public.admin_requests where id = a.request_id for update;
  select * into p from public.profiles where id = me;

  if r.request_type = 'lineage_request' then
    mn := btrim(regexp_replace(coalesce(p_values ->> 'mother_name', ''), '\s+', ' ', 'g'));
    if coalesce(array_length(string_to_array(nullif(mn, ''), ' '), 1), 0) < 2 then
      raise exception 'يُرجى كتابة اسم الوالدة' using errcode = '22023', hint = 'name_required';
    end if;
    if length(mn) > 120 then
      raise exception 'الاسم طويل' using errcode = '22023', hint = 'name_too_long';
    end if;
    d := case when r.details is not null and r.details ~ '^\s*\{' then r.details::jsonb else '{}'::jsonb end;
    d := d || jsonb_build_object(
      'mother_typed_name', mn,
      'mother_name', mn || ' ' || coalesce(d ->> 'mother_family', 'المحمدعلي'),
      'summary', 'نسب ' || coalesce(nullif(btrim(p.full_name), ''), '') || ': الوالدة ' || mn || ' '
                 || coalesce(d ->> 'mother_family', 'المحمدعلي') || ' · الوالد ' || coalesce(d ->> 'father_name', ''));
    perform set_config('app.lineage_rpc', 'on', true);
    update public.admin_requests set details = d::text where id = r.id;
    perform set_config('app.lineage_rpc', '', true);
  else
    -- البيانات حُفظت في ملفه من مربّع التسجيل — المطلوب يجب أن يكون موجوداً الآن
    foreach f in array a.fields loop
      if (f = 'full_name' and coalesce(array_length(string_to_array(nullif(btrim(p.full_name), ''), ' '), 1), 0) < 2)
         or (f = 'birth_date' and p.birth_date is null)
         or (f = 'gender' and lower(coalesce(p.gender, '')) not in ('male', 'female'))
         or (f = 'family' and nullif(btrim(coalesce(p.family_name, '')), '') is null)
         or (f = 'photo' and nullif(btrim(coalesce(p.avatar_url, '')), '') is null) then
        raise exception 'يُرجى إدخال %', public.join_completion_field_label(f) using errcode = '22023', hint = 'missing_value';
      end if;
    end loop;
  end if;

  update public.join_completion_asks set answered_at = now() where id = a.id;

  who := coalesce(nullif(btrim(p.full_name), ''), 'العضو');
  insert into public.notifications (target_member_id, title, body, kind, created_by)
  select s.id, 'تم استكمال البيانات', who || ' استكمل البيانات المطلوبة — يُرجى مراجعة الطلب', 'admin', me
    from public.profiles s
   where s.role in ('owner', 'admin', 'monitor') and s.status = 'active' and s.id <> me;
end;
$function$;

revoke all on function public.join_completion_field_label(text) from public, anon;
revoke all on function public.ask_join_completion(uuid, text[], text) from public, anon;
revoke all on function public.my_completion_ask() from public, anon;
revoke all on function public.answer_completion_ask(jsonb) from public, anon;
grant execute on function public.join_completion_field_label(text) to authenticated;
grant execute on function public.ask_join_completion(uuid, text[], text) to authenticated;
grant execute on function public.my_completion_ask() to authenticated;
grant execute on function public.answer_completion_ask(jsonb) to authenticated;
