-- «نبّهه يضيف صورة» + التذكير التلقائي (طلب المالك ٢٠٢٦-١١-٢٦، الوحدة P1):
--   «اذا حساب مسجل و مو حاط صورة بملفه … نحط زر ينبهه يحط صورة شخصية» · «ابى تذكير طلب اضافة صورة شخصية»
--   · «مابي التنبيه يكون بشكل يومي كل ما يدخل التطبيق».
-- NOT APPLIED — يطبّقه المدير بعد المراجعة. فوق 20261111160000_photo_change_request (مطبَّق) — نفس الجدول والإشعار
-- (kind = photo_change_request) والمشغّل الذي يغلق الطلب حين تُضاف الصورة. التطبيقات تعمل قبله وبعده.
--
-- ١) photo_change_requests:
--    • reminders_sent int (≥ 0): كم مرة أُعيد إشعار الطلب المفتوح (التذكير التلقائي، «ذكّره الحين»، التنبيه الجماعي).
--    • السبب صار اختيارياً حين لا صورة للعضو (طلب «أضف صورتك») — القيد ٠–٢٠٠ حرف بدل ١–٢٠٠، والدالة تبقى تشترطه
--      حين للعضو صورة (طلب «غيّر صورتك» كما كان حرفياً).
--    • القراءة: notified_at و reminders_sent تُقرأ من التطبيقات الآن (الإدارة: «نُبّه قبل 5 أيام · ذُكّر 1 من 3»؛ العضو:
--      مربّعه يظهر مرة لكل إشعار = معرّف الطلب + notified_at). requested_by/resolved_by/hid_photo تبقى مخفية، والصفوف
--      كما هي (RLS: الطاقم الكل، والعضو طلبه المفتوح فقط).
-- ٢) request_photo_change(p_member, p_reason, p_hide): نفس التوقيع والأدوار والأخطاء والترتيب. الجديد:
--    • العضو بلا صورة (avatar_url وphoto_url فارغان): السبب اختياري، لا إخفاء (لا صورة تُخفى)، والإشعار
--      «أضف صورتك الشخصية» / «تطلب منك الإدارة إضافة صورة شخصية لملفك.» (details.photo_add = true).
--      الأنثى بلا صورة ترفض (hint = female_no_photo): «لا صور للإناث» (المشغّل الحي no_photo_for_females يفرّغ أي صورة
--      لأنثى، فطلب الإضافة لا يُنفَّذ أبداً ويبقى يذكّرها).
--    • له صورة: كما كان حرفياً (السبب مطلوب ≤ ٢٠٠، «طلب تغيير الصورة الشخصية» / «يرجى تغيير صورتك الشخصية — السبب: …»).
--    • إعادة الإشعار لطلب مفتوح (بعد دقيقة من آخر إشعار — نفس منع الإزعاج) تُعدّ تذكيراً: reminders_sent + 1.
-- ٣) request_photo_add_all() → int (المالك والمدير فقط، current_user_role()؛ غيرهما 42501 not_allowed):
--    لكل عضو له حساب دخول (profile_has_login)، حيّ، status = active، ليس pending، ليس المتصل، ليس مالكاً إلا لمالك،
--    ليس أنثى، بلا صورة، وليس له طلب مفتوح أُشعر خلال ٧ أيام: ينشئ الطلب (أو يحدّث المفتوح القديم ويعدّه تذكيراً)
--    ويرسل إشعاراً واحداً بنص «أضف صورتك»، ويرجع عدد من وصله. التكرار فوراً يرجع 0.
-- ٤) photo_requests_remind_tick() → int (pg_cron 'photo-requests-remind' يومياً 15:00 UTC = 18:00 الكويت؛ داخلية فقط):
--    لكل طلب مفتوح (المفتوح = الصورة لم تُضف أو لم تتغيّر — المشغّل يغلقه عند التغيير) عضوه حيّ مفعّل له حساب:
--    إن مضت app_config.photo_request_remind_days (افتراضي 3؛ 0 = مطفأ) أيام تقويمية بتوقيت الكويت على آخر إشعار
--    وreminders_sent < app_config.photo_request_max_reminders (افتراضي 3؛ 0 = مطفأ): إشعار تذكير واحد بنفس النوع
--    (الضغط يفتح المربّع) «تذكير: أضف صورتك الشخصية» / «ما زالت الإدارة بانتظار صورتك الشخصية.» — أو للتغيير
--    «تذكير: غيّر صورتك الشخصية» / «ما زالت الإدارة بانتظار صورتك الجديدة — السبب: …» — ثم notified_at = now()
--    وreminders_sent + 1. المجمّد والمحذوف والمتوفى والمعلّق يُتخطّون. المرسل «الإدارة» (created_by فارغ).
-- ٥) app_config: photo_request_remind_days (0–30، 3) وphoto_request_max_reminders (0–10، 3) — فئة «الشجرة» بجانب
--    photo_reminder_days، يعدّلهما المالك بـ set_app_config («التطبيق» ← «قواعد الأعضاء»). مفاتيح int عادية — لا تمسّ
--    private.admin_role_matrix_problem.
--
-- التراجع: rollback/20261126180000_photo_add_request_rollback.sql
-- تجربة: cd supabase/tests/family_links && node photo_add_request.test.mjs

-- ─── ١) الجدول ───
alter table public.photo_change_requests
  add column if not exists reminders_sent integer not null default 0;

alter table public.photo_change_requests drop constraint if exists photo_change_requests_reminders_sent;
alter table public.photo_change_requests
  add constraint photo_change_requests_reminders_sent check (reminders_sent >= 0);

alter table public.photo_change_requests drop constraint if exists photo_change_requests_reason_len;
alter table public.photo_change_requests
  add constraint photo_change_requests_reason_len check (char_length(btrim(reason)) <= 200);

grant select (notified_at, reminders_sent) on public.photo_change_requests to authenticated;

comment on column public.photo_change_requests.reminders_sent is
  'كم مرة أُعيد إشعار الطلب المفتوح (تذكير تلقائي، «ذكّره الحين»، تنبيه جماعي) — ٢٠٢٦-١١-٢٦';

-- ─── ٢) الطلب (فردي) ───
create or replace function public.request_photo_change(p_member uuid, p_reason text, p_hide boolean default false)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_me uuid := public.current_profile_id();
  v_role text := coalesce(public.current_user_role(), 'anonymous');
  v_reason text := btrim(regexp_replace(coalesce(p_reason, ''), '\s+', ' ', 'g'));
  v_hide boolean := coalesce(p_hide, false);
  v_member public.profiles%rowtype;
  v_req public.photo_change_requests%rowtype;
  v_notify boolean := true;
  v_has_photo boolean;
begin
  if v_me is null or v_role not in ('owner', 'admin', 'monitor') then
    raise exception 'طلب تغيير الصورة للمالك والمدير والمراقب فقط'
      using errcode = '42501', hint = 'not_allowed';
  end if;
  if char_length(v_reason) > 200 then
    raise exception 'سبب الطلب مطلوب (حتى ٢٠٠ حرف)' using errcode = '22023', hint = 'bad_reason';
  end if;

  -- قفل سجل العضو أولاً (نفس ترتيب المشغّل وcancel_photo_change: الملف ثم الطلب)
  select * into v_member from public.profiles where id = p_member for update;
  if not found then
    raise exception 'العضو غير موجود' using errcode = 'P0002', hint = 'member_not_found';
  end if;
  if v_member.id = v_me then
    raise exception 'لا يُطلب تغيير صورتك منك — غيّرها من «حسابي»' using errcode = '22023', hint = 'own_profile';
  end if;
  if v_member.role = 'owner' and v_role <> 'owner' then
    raise exception 'لا يُطلب هذا من المالك' using errcode = '42501', hint = 'owner_protected';
  end if;
  if coalesce(v_member.is_deceased, false) then
    raise exception 'العضو متوفى' using errcode = '22023', hint = 'deceased';
  end if;
  if not public.profile_has_login(p_member) then
    raise exception 'ليس للعضو حساب في التطبيق' using errcode = '22023', hint = 'no_account';
  end if;

  v_has_photo := nullif(btrim(coalesce(v_member.avatar_url, '')), '') is not null
              or nullif(btrim(coalesce(v_member.photo_url, '')), '') is not null;
  if v_has_photo and char_length(v_reason) = 0 then
    raise exception 'سبب الطلب مطلوب (حتى ٢٠٠ حرف)' using errcode = '22023', hint = 'bad_reason';
  end if;
  if not v_has_photo then
    -- لا صور للإناث (no_photo_for_females يفرّغها) — طلب إضافة لا يُنفَّذ أبداً
    if lower(coalesce(v_member.gender, '')) = 'female' then
      raise exception 'لا صور للإناث في التطبيق' using errcode = '22023', hint = 'female_no_photo';
    end if;
    v_hide := false;  -- لا صورة تُخفى
  end if;

  select * into v_req from public.photo_change_requests
   where member_id = p_member and resolved_at is null
   for update;
  if found then
    v_notify := v_req.notified_at is null or v_req.notified_at < now() - interval '1 minute';
    update public.photo_change_requests
       set reason = v_reason,
           hide_photo = v_req.hide_photo or v_hide,
           requested_by = v_me,
           requested_at = now(),
           notified_at = case when v_notify then now() else notified_at end,
           reminders_sent = reminders_sent + case when v_notify then 1 else 0 end
     where id = v_req.id
     returning * into v_req;
  else
    insert into public.photo_change_requests (member_id, reason, hide_photo, requested_by, notified_at)
    values (p_member, v_reason, v_hide, v_me, now())
    returning * into v_req;
  end if;

  -- الإخفاء: نفس مفتاح خصوصية العضو — فقط إن كانت ظاهرة (ما أخفاه هو يبقى اختياره)
  if v_hide and not coalesce(v_member.is_photo_hidden, false) then
    update public.profiles set is_photo_hidden = true where id = p_member;
    update public.photo_change_requests set hid_photo = true where id = v_req.id;
  end if;

  if v_notify then
    insert into public.notifications (target_member_id, title, body, kind, created_by, is_read, details, subject_member_id)
    values (p_member,
            case when v_has_photo then 'طلب تغيير الصورة الشخصية' else 'أضف صورتك الشخصية' end,
            case when v_has_photo then 'يرجى تغيير صورتك الشخصية — السبب: ' || rtrim(v_reason, '.۔。 ') || '.'
                 else 'تطلب منك الإدارة إضافة صورة شخصية لملفك.' end,
            'photo_change_request', v_me, false,
            jsonb_build_object('photo_change_request_id', v_req.id, 'reason', v_reason, 'photo_add', not v_has_photo),
            p_member);
  end if;

  return v_req.id;
end;
$function$;

revoke all on function public.request_photo_change(uuid, text, boolean) from public, anon;
grant execute on function public.request_photo_change(uuid, text, boolean) to authenticated;

-- ─── ٣) «نبّههم كلهم» ───
create or replace function public.request_photo_add_all()
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_me uuid := public.current_profile_id();
  v_role text := coalesce(public.current_user_role(), 'anonymous');
  v_id uuid;
  v_req public.photo_change_requests%rowtype;
  v_n integer := 0;
begin
  if v_me is null or v_role not in ('owner', 'admin') then
    raise exception 'التنبيه الجماعي للمالك والمدير فقط'
      using errcode = '42501', hint = 'not_allowed';
  end if;

  for v_id in
    select p.id
      from public.profiles p
     where p.id <> v_me
       and not coalesce(p.is_deceased, false)
       and p.status = 'active'
       and coalesce(p.role, '') <> 'pending'
       and (coalesce(p.role, '') <> 'owner' or v_role = 'owner')
       and lower(coalesce(p.gender, '')) <> 'female'
       and nullif(btrim(coalesce(p.avatar_url, '')), '') is null
       and nullif(btrim(coalesce(p.photo_url, '')), '') is null
       and not exists (select 1 from public.photo_change_requests q
                        where q.member_id = p.id and q.resolved_at is null
                          and q.notified_at >= now() - interval '7 days')
       and public.profile_has_login(p.id)
     order by p.id
  loop
    -- نفس ترتيب القفل (الملف ثم الطلب)، وإعادة الفحص بعده (صورة أُضيفت للتو تُتخطّى)
    perform 1 from public.profiles p
     where p.id = v_id
       and nullif(btrim(coalesce(p.avatar_url, '')), '') is null
       and nullif(btrim(coalesce(p.photo_url, '')), '') is null
       for update;
    if not found then
      continue;
    end if;
    select * into v_req from public.photo_change_requests
     where member_id = v_id and resolved_at is null
     for update;
    if found then
      if v_req.notified_at is not null and v_req.notified_at >= now() - interval '7 days' then
        continue;
      end if;
      update public.photo_change_requests
         set requested_by = v_me, requested_at = now(), notified_at = now(),
             reminders_sent = reminders_sent + 1
       where id = v_req.id
       returning * into v_req;
    else
      insert into public.photo_change_requests (member_id, reason, hide_photo, requested_by, notified_at)
      values (v_id, '', false, v_me, now())
      returning * into v_req;
    end if;

    insert into public.notifications (target_member_id, title, body, kind, created_by, is_read, details, subject_member_id)
    values (v_id, 'أضف صورتك الشخصية', 'تطلب منك الإدارة إضافة صورة شخصية لملفك.',
            'photo_change_request', v_me, false,
            jsonb_build_object('photo_change_request_id', v_req.id, 'reason', v_req.reason, 'photo_add', true, 'bulk', true),
            v_id);
    v_n := v_n + 1;
  end loop;

  return v_n;
end;
$function$;

revoke all on function public.request_photo_add_all() from public, anon;
grant execute on function public.request_photo_add_all() to authenticated;

-- ─── ٤) التذكير التلقائي ───
create or replace function public.photo_requests_remind_tick()
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_days integer := coalesce((select (c.value #>> '{}')::integer from public.app_config c
                               where c.key = 'photo_request_remind_days'), 3);
  v_max integer := coalesce((select (c.value #>> '{}')::integer from public.app_config c
                              where c.key = 'photo_request_max_reminders'), 3);
  v_today date := (now() at time zone 'Asia/Kuwait')::date;
  r record;
  v_has_photo boolean;
  v_reason text;
  v_n integer := 0;
begin
  if v_days <= 0 or v_max <= 0 then
    return 0;
  end if;

  for r in
    select q.id, q.member_id, q.reason, q.reminders_sent, p.avatar_url, p.photo_url, p.gender
      from public.photo_change_requests q
      join public.profiles p on p.id = q.member_id
     where q.resolved_at is null
       and q.reminders_sent < v_max
       and v_today - (coalesce(q.notified_at, q.requested_at) at time zone 'Asia/Kuwait')::date >= v_days
       and p.status = 'active'
       and coalesce(p.role, '') <> 'pending'
       and not coalesce(p.is_deceased, false)
       and public.profile_has_login(p.id)
     order by q.notified_at nulls first
       for update of q skip locked
  loop
    v_has_photo := nullif(btrim(coalesce(r.avatar_url, '')), '') is not null
                or nullif(btrim(coalesce(r.photo_url, '')), '') is not null;
    if not v_has_photo and lower(coalesce(r.gender, '')) = 'female' then
      continue;
    end if;
    v_reason := rtrim(btrim(coalesce(r.reason, '')), '.۔。 ');

    update public.photo_change_requests
       set notified_at = now(), reminders_sent = reminders_sent + 1
     where id = r.id;

    insert into public.notifications (target_member_id, title, body, kind, created_by, is_read, details, subject_member_id)
    values (r.member_id,
            case when v_has_photo then 'تذكير: غيّر صورتك الشخصية' else 'تذكير: أضف صورتك الشخصية' end,
            case when not v_has_photo then 'ما زالت الإدارة بانتظار صورتك الشخصية.'
                 when v_reason = '' then 'ما زالت الإدارة بانتظار صورتك الجديدة.'
                 else 'ما زالت الإدارة بانتظار صورتك الجديدة — السبب: ' || v_reason || '.' end,
            'photo_change_request', null, false,
            jsonb_build_object('photo_change_request_id', r.id, 'reason', r.reason, 'photo_add', not v_has_photo,
                               'reminder', r.reminders_sent + 1),
            r.member_id);
    v_n := v_n + 1;
  end loop;

  return v_n;
end;
$function$;

-- داخلية فقط (pg_cron)
revoke all on function public.photo_requests_remind_tick() from public, anon, authenticated;

-- ─── ٥) الإعدادات ───
insert into public.app_config (key, value, default_value, kind, min_value, max_value, category, label_ar, help_ar, is_public, sort)
values ('photo_request_remind_days', '3'::jsonb, '3'::jsonb, 'int', 0, 30, 'tree',
        'تذكير طلب الصورة (كل كم يوم)',
        'إذا طلبت الإدارة من عضو إضافة صورته أو تغييرها ولم يفعل، يصله تذكير بعد هذه الأيام. 0 = بلا تذكير.', false, 65),
       ('photo_request_max_reminders', '3'::jsonb, '3'::jsonb, 'int', 0, 10, 'tree',
        'عدد تذكيرات طلب الصورة',
        'أقصى عدد للتذكير لكل طلب، ثم يبقى الطلب مفتوحاً بلا تذكير. 0 = بلا تذكير.', false, 65)
on conflict (key) do nothing;

-- ─── ٦) الجدولة (pg_cron بتوقيت UTC) — cron.schedule بالاسم نفسه يحدّث المهمة بدل تكرارها ───
select cron.schedule('photo-requests-remind', '0 15 * * *', 'select public.photo_requests_remind_tick()');
