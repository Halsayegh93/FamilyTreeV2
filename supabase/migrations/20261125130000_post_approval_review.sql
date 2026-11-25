-- «مراجعة بعد الموافقة» (طلب المالك ٢٠٢٦-١١-٢٥: «نحط مراجعة في الطلبات الواردة و المنجزة و اشعارات — يكون موافقة
-- عادية ولكن بعد الموافقة في مراجعة عند شخص مختص يراجع الى صار بالطلب»، الخيار «أ»: كل طلب يُقبل يدخل المراجعة)
-- NOT APPLIED — يُطبَّق بموافقة المالك. التطبيقات تعمل قبله (الأعمدة غائبة = لا مراجعة، كما اليوم).
--
-- الموافقة نفسها لا تتغيّر أبداً (decide_admin_request، مسار الموافقات، الكتابة المباشرة من الأندرويد والموقع
-- والآيفون القديم). بعد أن يصير الطلب «مقبولاً» يعلَّم «بانتظار المراجعة»، ويراجعه المختص: «سليم» أو «فيه ملاحظة».
--
-- ١) أعمدة في public.admin_requests:
--    review_status text  — NULL = لا يخضع للمراجعة (القديم، المرفوض، المعلّق، رسائل التواصل) · 'pending' · 'ok' · 'flagged'
--    reviewed_by   uuid  — من راجع (معرّف ملفه)
--    reviewed_at   timestamptz
--    review_note   text  — ملاحظة المراجع (مطلوبة مع 'flagged')
--    «من وافق ومتى» = العمودان الموجودان replied_by / replied_at (لا عمود جديد): المشغّل يملؤهما عند دخول المراجعة
--    إن غابا، ويكتب الفاعل الحقيقي إن أرسل التطبيق غيره. approved_by (اعتماد المدير في مسار الموافقات) كما هو.
-- ٢) المفتاح app_settings.approvals_post_review (افتراضياً شغّال) — يعدّله المالك بسياسة app_settings الحالية
--    («Owner can update app_settings»)، ويقرؤه كل مسجّل (المدير يطّلع). إطفاؤه يوقف دخول طلبات جديدة للمراجعة فقط؛
--    ما ينتظر المراجعة يبقى ويُراجَع.
-- ٣) المشغّل trg_zzz_admin_request_post_review (قبل الإدراج والتحديث، بعد trg_admin_request_payload_lock و
--    trg_zz_admin_request_workflow وقبل trg_zzz_admin_request_sent_info بالترتيب الأبجدي — فلا يغيّر قراراتها):
--    • الحالة تصير 'approved' (من أي حالة أخرى، بأي مسار ومن أي أحد حتى الصيانة) والمفتاح شغّال والنوع داخل المسار
--      (workflow_specialist_role(النوع) ليس NULL — كل الأنواع عدا contact_message) → review_status = 'pending'
--      (ومسح أي مراجعة سابقة: إعادة فتح ثم قبول = مراجعة جديدة).
--    • الطلب يترك 'approved' قبل أن يُراجَع (أُعيد فتحه/رُفض) → review_status = NULL. المراجَع يبقى للتاريخ.
--    • أعمدة المراجعة لا يكتبها أحد مباشرة (تبقى قيمتها بصمت، مثل sent_from) إلا review_admin_request (علم المعاملة
--      approvals.post_review) أو الصيانة (مفتاح الخدمة، SQL بلا مستخدم). الإدراج من مستخدم يمسحها.
--    • لا تعبئة للقديم: الطلبات المقبولة قبل هذا الترحيل تبقى NULL.
--    • الإدراج بحالة 'approved' (سجلّ «تعديل مباشر» من الإدارة) لا يدخل المراجعة — ليس طلباً.
-- ٤) review_admin_request(p_request_id uuid, p_result text 'ok'|'flagged', p_note text default null) — SECURITY DEFINER:
--    • المراجع: المالك دائماً، أو مختص النوع (is_workflow_specialist: المشرف للبلاغات، المراقب لغيرها؛ لا مختص نشط
--      بهذا الدور → المالك/المدير مكانه).
--    • لا أحد يراجع موافقة هو فاعلها (replied_by أو approved_by) ولا طلبه هو (صاحبه أو المعني به) — إلا المالك.
--    • review_status = 'pending' شرط؛ «فيه ملاحظة» تحتاج ملاحظة (حتى ١٠٠٠ حرف).
--    • «فيه ملاحظة» → إشعار (kind 'admin'، details.type = 'post_review' و details.request_id — عمودا الطلب في
--      الإشعار فارغان عمداً مثل «مسار الموافقات» حتى لا تُظهر النسخ القديمة «قبول» سريعاً) لمن وافق (replied_by
--      واعتماد المدير approved_by) «ملاحظة على طلب وافقت عليه»، وللمالك والمدير النشطين «ملاحظة مراجعة على طلب مقبول».
--      لا يُشعَر المراجع نفسه. «سليم» بلا إشعار.
--    • يُسجَّل في admin_request_events (reviewed_ok / reviewed_flagged) إن وُجد السجلّ (20261111150000).
--    أخطاؤه بـ hint: not_allowed · request_not_found · not_in_review · already_reviewed · own_approval · own_request ·
--    note_required · bad_payload.
--
-- التراجع: supabase/rollback/20261125130000_post_approval_review_rollback.sql
-- تجربة: cd supabase/tests/family_links && node post_approval_review.test.mjs

-- ═══ ١) الأعمدة ═══
alter table public.admin_requests
  add column if not exists review_status text,
  add column if not exists reviewed_by   uuid,
  add column if not exists reviewed_at   timestamptz,
  add column if not exists review_note   text;
alter table public.admin_requests
  drop constraint if exists admin_requests_review_status_check,
  add constraint admin_requests_review_status_check check (review_status in ('pending', 'ok', 'flagged'));
create index if not exists admin_requests_review_pending_idx on public.admin_requests (replied_at desc)
  where review_status = 'pending';

comment on column public.admin_requests.review_status is
  'مراجعة بعد الموافقة (20261125130000): NULL لا يخضع · pending · ok · flagged — يكتبها السيرفر وحده';
comment on column public.admin_requests.reviewed_by is 'مراجعة بعد الموافقة: من راجع (معرّف ملفه)';
comment on column public.admin_requests.reviewed_at is 'مراجعة بعد الموافقة: وقت المراجعة';
comment on column public.admin_requests.review_note is 'مراجعة بعد الموافقة: ملاحظة المراجع (مطلوبة مع flagged)';

-- ═══ ٢) المفتاح ═══
alter table public.app_settings
  add column if not exists approvals_post_review boolean not null default true;
comment on column public.app_settings.approvals_post_review is
  'مراجعة بعد الموافقة (طلب المالك ٢٠٢٦-١١-٢٥): كل طلب يُقبل يدخل مراجعة المختص — مطفأ = لا يدخل طلب جديد';

-- المفتاح شغّال؟ (يقرأ الإعداد بلا اعتبار لسياسات الجدول)
create or replace function public.post_review_on()
 returns boolean
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select coalesce((select bool_or(s.approvals_post_review) from public.app_settings s), false);
$function$;
revoke all on function public.post_review_on() from public, anon, authenticated;

-- ═══ ٣) المشغّل ═══
create or replace function public.trg_admin_request_post_review()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  maint   boolean := coalesce(auth.role() = 'service_role', false) or auth.uid() is null;
  via_rpc boolean := coalesce(current_setting('approvals.post_review', true), '') = 'on';
  me      uuid;
begin
  if tg_op = 'INSERT' then
    if not maint then
      new.review_status := null;
      new.reviewed_by   := null;
      new.reviewed_at   := null;
      new.review_note   := null;
    end if;
    return new;
  end if;

  -- أعمدة المراجعة: من review_admin_request أو الصيانة فقط — غيرهما تبقى قيمتها القديمة بصمت
  if not via_rpc and not maint then
    new.review_status := old.review_status;
    new.reviewed_by   := old.reviewed_by;
    new.reviewed_at   := old.reviewed_at;
    new.review_note   := old.review_note;
  end if;

  if new.status is not distinct from old.status then
    return new;
  end if;

  if new.status = 'approved' then
    -- النوع داخل المسار (= workflow_specialist_role(النوع) ليس NULL) والمفتاح شغّال
    if public.workflow_specialist_role(new.request_type) is null or not public.post_review_on() then
      return new;
    end if;
    -- صيانة كتبت مراجعة صريحة في التحديث نفسه: تبقى
    if maint and new.review_status is distinct from old.review_status then
      return new;
    end if;
    new.review_status := 'pending';
    new.reviewed_by   := null;
    new.reviewed_at   := null;
    new.review_note   := null;
    -- من وافق: الفاعل الحقيقي (مستخدم له ملف) — يملأ الغائب ويصحّح ما ليس هو
    me := public.current_profile_id();
    if not maint and me is not null and exists (select 1 from public.profiles p where p.id = me)
       and not coalesce(new.replied_by = any (array[me, auth.uid()]), false) then
      new.replied_by := me;
    end if;
    if new.replied_at is null then
      new.replied_at := now();
    end if;
  elsif old.status = 'approved' and old.review_status = 'pending' then
    -- ترك «مقبول» قبل المراجعة (أُعيد فتحه أو رُفض): لم يعد هناك ما يُراجَع
    new.review_status := null;
  end if;
  return new;
end;
$function$;
revoke all on function public.trg_admin_request_post_review() from public, anon, authenticated;

drop trigger if exists trg_zzz_admin_request_post_review on public.admin_requests;
create trigger trg_zzz_admin_request_post_review
  before insert or update on public.admin_requests
  for each row execute function public.trg_admin_request_post_review();

-- ═══ ٤) المراجعة ═══
create or replace function public.review_admin_request(p_request_id uuid, p_result text, p_note text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  uid      uuid := auth.uid();
  me       uuid := public.current_profile_id();
  my_role  text := coalesce(public.current_user_role(), 'pending');
  res      text := lower(btrim(coalesce(p_result, '')));
  note     text := nullif(btrim(coalesce(p_note, '')), '');
  r        public.admin_requests%rowtype;
  mine     uuid[];
  approver uuid[];
  me_name  text;
  body     text;
  n1       integer := 0;
  n2       integer := 0;
  at_      timestamptz := now();
begin
  if uid is null or me is null or my_role not in ('owner', 'admin', 'monitor', 'supervisor') then
    raise exception 'مراجعة الطلبات للإدارة فقط' using errcode = '42501', hint = 'not_allowed';
  end if;
  if res not in ('ok', 'flagged') then
    raise exception 'نتيجة المراجعة غير معروفة' using errcode = '22023', hint = 'bad_payload';
  end if;
  if res = 'flagged' and note is null then
    raise exception 'اكتب الملاحظة' using errcode = '22023', hint = 'note_required';
  end if;
  note := left(note, 1000);

  select * into r from public.admin_requests where id = p_request_id for update;
  if not found then
    raise exception 'الطلب غير موجود' using errcode = 'P0002', hint = 'request_not_found';
  end if;
  if r.status is distinct from 'approved' or r.review_status is null then
    raise exception 'هذا الطلب ليس بانتظار المراجعة' using errcode = 'P0001', hint = 'not_in_review';
  end if;
  if r.review_status <> 'pending' then
    raise exception 'راجعه غيرك قبلك' using errcode = 'P0001', hint = 'already_reviewed';
  end if;
  -- المراجع: المالك دائماً، أو مختص النوع (وبديله المالك/المدير حين لا مختص نشط)
  if my_role <> 'owner' and not public.is_workflow_specialist(r.request_type) then
    raise exception 'مراجعة هذا الطلب للمختص' using errcode = '42501', hint = 'not_allowed';
  end if;
  mine := array[uid, me];
  if my_role <> 'owner' then
    if r.replied_by = any (mine) or r.approved_by = any (mine) then
      raise exception 'لا تراجع موافقتك — يراجعها غيرك' using errcode = '42501', hint = 'own_approval';
    end if;
    if r.requester_id = any (mine) or r.member_id = any (mine) then
      raise exception 'لا تراجع طلبك — يراجعه غيرك' using errcode = '42501', hint = 'own_request';
    end if;
  end if;

  perform set_config('approvals.post_review', 'on', true);
  update public.admin_requests
     set review_status = res, reviewed_by = me, reviewed_at = at_, review_note = note
   where id = r.id;
  perform set_config('approvals.post_review', '', true);

  -- «ما تم في الطلب» إن وُجد السجلّ (20261111150000)
  if to_regprocedure('public.admin_request_log_event(uuid,text,uuid,text,text)') is not null then
    execute 'select public.admin_request_log_event($1, $2, $3, $4, $5)'
      using r.id, r.request_type, r.member_id, 'reviewed_' || res, note;
  end if;

  if res = 'flagged' then
    select coalesce(nullif(btrim(p.first_name), ''), nullif(split_part(btrim(p.full_name), ' ', 1), ''), 'المراجع')
      into me_name from public.profiles p where p.id = me;
    body := coalesce(me_name, 'المراجع') || ' راجع ' || public.admin_request_label(r.request_type)
            || ' ووجد ملاحظة: ' || note;
    approver := array(select distinct x from unnest(array[r.replied_by, r.approved_by]) x where x is not null);
    insert into public.notifications (target_member_id, title, body, kind, created_by, details)
    select t, 'ملاحظة على طلب وافقت عليه', body, 'admin', me,
           jsonb_build_object('type', 'post_review', 'request_id', r.id, 'request_type', r.request_type,
                              'action', 'flagged', 'note', note, 'reviewer_id', me)
    from unnest(approver) t
    where t is distinct from me and exists (select 1 from public.profiles p where p.id = t);
    get diagnostics n1 = row_count;
    insert into public.notifications (target_member_id, title, body, kind, created_by, details)
    select p.id, 'ملاحظة مراجعة على طلب مقبول', body, 'admin', me,
           jsonb_build_object('type', 'post_review', 'request_id', r.id, 'request_type', r.request_type,
                              'action', 'flagged', 'note', note, 'reviewer_id', me)
    from public.profiles p
    where p.role in ('owner', 'admin') and p.status = 'active' and p.id <> me and not (p.id = any (approver));
    get diagnostics n2 = row_count;
  end if;

  return jsonb_build_object('ok', true, 'request_id', r.id, 'review_status', res, 'reviewed_by', me,
                            'reviewed_at', at_, 'review_note', note, 'notified', n1 + n2);
end;
$function$;
revoke all on function public.review_admin_request(uuid, text, text) from public, anon;
grant execute on function public.review_admin_request(uuid, text, text) to authenticated;
comment on function public.review_admin_request(uuid, text, text) is
  'مراجعة بعد الموافقة (20261125130000): المختص (أو المالك) يراجع طلباً مقبولاً — ok | flagged بملاحظة';
