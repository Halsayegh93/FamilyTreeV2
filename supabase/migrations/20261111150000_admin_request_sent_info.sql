-- «من أرسل الطلب ومن أين» (طلب المالك ٢٠٢٦-١١-١١، «نعم ابدأ» على التصميم والسيرفر):
-- NOT APPLIED — يُطبَّق بموافقة المالك. التطبيقات تعمل قبله (ترجع للمسار المستنتج و«غير مسجّل»).
--
-- ١) عمودان جديدان في public.admin_requests:
--    sent_from jsonb — مسار الإرسال من التطبيق: مصفوفة ١–٥ خطوات {"icon": نص ≤٤٠، "title": نص ≤١٢٠}
--                      (مثال: [{"icon":"tree.fill","title":"شجرة النساء"},{"icon":"person.fill","title":"…"},{"icon":"plus","title":"طلب إضافة أبناء"}]).
--                      أي شكل آخر يُحفظ NULL — لا يُرفض الإدراج بسببه أبداً. يُطبَّع: الحقلان فقط، المسافات مطويّة.
--    sent_via  jsonb — يكتبه السيرفر وحده من ترويسات الطلب (request.headers في PostgREST)، وما يرسله العميل يُستبدل دائماً:
--                      platform: x-app-platform (ios|android|web)، وإلا من x-client-info (supabase-swift → ios،
--                      supabase-dart/flutter → android، supabase-js → web)، وإلا unknown؛ مفتاح الخدمة → server.
--                      app_version / app_build: x-app-version / x-app-build (حروف وأرقام و . _ + - حتى ٢٠).
--                      client: x-client-info (ASCII مطبوع حتى ٦٠). at: وقت الإدراج.
--                      بلا ترويسات (SQL صيانة، pg_cron، دوال بلا طلب) → {"platform":"server","at":…}.
--    الطلبات التي تُنشئها دوال السيرفر داخل طلب من التطبيق (relative_add، lineage_request، account_delete،
--    privacy_request، بلاغ الحظر…) تأخذ sent_via من ترويسات ذلك الطلب، وsent_from يبقى NULL.
-- ٢) لا يتغيّر العمودان بعد الإدراج لأي أحد (حتى مفتاح الخدمة والصيانة): التحديث يُبقي قيمتهما القديمة بصمت.
-- ٣) «من ردّ ومتى» عند غيابه: إغلاق طلب معلّق (pending → غيره) بلا replied_at/replied_by يملؤهما السيرفر:
--    replied_at = now()، replied_by = current_profile_id() إن كان ملفاً موجوداً (الإدارة من التطبيق أو
--    decide_admin_request). كانت كل موافقات decide_admin_request (والعلاقات relative_add فيها) وتفعيل الانضمام
--    المباشر من الآيفون تُغلق بلا replied_by. ما يُرسله العميل صريحاً يبقى كما هو.
--    approved_by لا يُمسّ: عمود «مسار الموافقات» (اعتماد المدير) — يبقى NULL والمفتاح مطفأ أو النوع خارج المسار.
-- ٤) «ما تم في الطلب» (طلب المالك: «شنو كل طلب صار فيه ومن سواه من الإدارة»): سجلّ إلحاقي جديد
--    public.admin_request_events (request_id, request_type, subject_id, action, actor_id, actor_role, note, at)
--    يملؤه مشغّل AFTER على admin_requests لكل مسار (التطبيقات الثلاثة، دوال السيرفر، الصيانة) بلا تغيير في التطبيقات:
--      إدراج → sent · الحالة: approved | executed (بعد اعتماد المدير) | replied (رسالة تواصل) | rejected | reopened |
--      status:<قيمة أخرى> · المسار: recommended_approve | recommended_reject | manager_approved | info_requested |
--      info_replied | returned | stage:<…> | claimed | released | escalated · رد بلا إغلاق: replied ·
--      نقل الطلب (دمج الملفات): moved · الحذف: deleted (وwithdrawn إن حذفه صاحبه).
--    ومشغّل AFTER على profiles: الإدارة تفعّل حساباً معلّقاً (الدور يترك pending أو الحالة pending → active) →
--      member_activated مربوطاً بآخر طلب انضمام/ربط له. التفعيل الذاتي (adopt_tree_profile) لا يُسجَّل.
--    actor_id = current_profile_id() إن كان ملفاً موجوداً، actor_role = current_user_role() (أو server للصيانة/الخدمة).
--    القراءة: الإدارة حسب نوع الطلب (can_handle_admin_request) — لا كتابة لأي مستخدم. لا تعبئة للقديم.
--    request_id بلا مفتاح أجنبي: السجل يبقى بعد حذف الطلب.
-- المشغّل trg_zzz_admin_request_sent_info يعمل آخر مشغّلات BEFORE (الترتيب أبجدي: بعد
-- trg_admin_requests_registration_gate · trg_guard_admin_request_insert · trg_zz_admin_request_stage في الإدراج،
-- وبعد trg_admin_request_payload_lock · trg_zz_admin_request_workflow في التحديث) فلا يغيّر قراراتها.
-- الصلاحيات: authenticated له insert/update على الجدول كاملاً (منح الجدول يشمل العمودين)، وRLS كما هي.
-- لا واجهة ولا نشر realtime يعدّد أعمدة admin_requests (فحص الحي ٢٠٢٦-١١-١١).
--
-- التراجع: rollback/20261111150000_admin_request_sent_info_rollback.sql
-- تجربة: cd supabase/tests/family_links && node admin_request_sent_info.test.mjs

alter table public.admin_requests
  add column if not exists sent_from jsonb,
  add column if not exists sent_via  jsonb;

comment on column public.admin_requests.sent_from is
  'مسار الإرسال من التطبيق: [{icon,title}] ١–٥ خطوات، يُنظَّف عند الإدراج ولا يتغيّر بعده (20261111150000)';
comment on column public.admin_requests.sent_via is
  'الجهاز من ترويسات الطلب: {platform, app_version, app_build, client, at} — يكتبه السيرفر وحده ولا يتغيّر (20261111150000)';

create or replace function public.trg_admin_request_sent_info()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  src   jsonb;
  clean jsonb;
  e     jsonb;
  ic    text;
  ti    text;
  raw   text;
  h     jsonb;
  ci    text;
  plat  text;
  ver   text;
  bld   text;
  me    uuid;
  safe  constant text := '^[0-9A-Za-z][0-9A-Za-z._+-]{0,19}$';
begin
  if tg_op = 'UPDATE' then
    -- لا يتغيّران بعد الإدراج — لأي أحد
    new.sent_from := old.sent_from;
    new.sent_via  := old.sent_via;
    -- من أغلق الطلب ومتى، إن لم يُكتبا
    if old.status is not distinct from 'pending' and new.status is distinct from 'pending' then
      if new.replied_at is null then
        new.replied_at := now();
      end if;
      if new.replied_by is null then
        me := public.current_profile_id();
        if me is not null and exists (select 1 from public.profiles p where p.id = me) then
          new.replied_by := me;
        end if;
      end if;
    end if;
    return new;
  end if;

  -- ═══ الإدراج ═══
  -- ١) المسار: شكل صحيح أو NULL (لا رفض)
  src := new.sent_from;
  new.sent_from := null;
  begin
    if jsonb_typeof(src) = 'array' and jsonb_array_length(src) between 1 and 5 then
      clean := '[]'::jsonb;
      for e in select value from jsonb_array_elements(src) loop
        if jsonb_typeof(e) is distinct from 'object'
           or jsonb_typeof(e -> 'icon') is distinct from 'string'
           or jsonb_typeof(e -> 'title') is distinct from 'string' then
          clean := null;
          exit;
        end if;
        ic := btrim(e ->> 'icon');
        ti := btrim(regexp_replace(e ->> 'title', '\s+', ' ', 'g'));
        if ti = '' or char_length(ti) > 120 or char_length(ic) > 40 or ic !~ '^[A-Za-z0-9._-]*$' then
          clean := null;
          exit;
        end if;
        clean := clean || jsonb_build_array(jsonb_build_object('icon', ic, 'title', ti));
      end loop;
      new.sent_from := clean;
    end if;
  exception when others then
    new.sent_from := null;
  end;

  -- ٢) الجهاز: من ترويسات الطلب فقط (ما أرسله العميل يُستبدل)
  begin
    raw := nullif(btrim(coalesce(current_setting('request.headers', true), '')), '');
    if raw is not null then
      begin
        h := raw::jsonb;
      exception when others then
        h := null;
      end;
    end if;
    if h is null or jsonb_typeof(h) is distinct from 'object' then
      new.sent_via := jsonb_build_object('platform', 'server', 'at', now());
    else
      ci   := nullif(left(regexp_replace(coalesce(h ->> 'x-client-info', ''), '[^ -~]', '', 'g'), 60), '');
      plat := lower(btrim(coalesce(h ->> 'x-app-platform', '')));
      if plat not in ('ios', 'android', 'web') then
        plat := case
          when lower(coalesce(ci, '')) like 'supabase-swift%' then 'ios'
          when lower(coalesce(ci, '')) like 'supabase-dart%'
            or lower(coalesce(ci, '')) like 'supabase-flutter%' then 'android'
          when lower(coalesce(ci, '')) like 'supabase-js%' then 'web'
          else 'unknown' end;
      end if;
      if coalesce(auth.role(), '') = 'service_role' then
        plat := 'server';
      end if;
      ver := btrim(coalesce(h ->> 'x-app-version', ''));
      bld := btrim(coalesce(h ->> 'x-app-build', ''));
      new.sent_via := jsonb_strip_nulls(jsonb_build_object(
        'platform',    plat,
        'app_version', case when ver ~ safe then ver end,
        'app_build',   case when bld ~ safe then bld end,
        'client',      ci,
        'at',          now()));
    end if;
  exception when others then
    new.sent_via := jsonb_build_object('platform', 'unknown', 'at', now());
  end;
  return new;
end;
$function$;

revoke all on function public.trg_admin_request_sent_info() from public, anon, authenticated;

drop trigger if exists trg_zzz_admin_request_sent_info on public.admin_requests;
create trigger trg_zzz_admin_request_sent_info
  before insert or update on public.admin_requests
  for each row execute function public.trg_admin_request_sent_info();

-- ═══ ٤) «ما تم في الطلب»: سجلّ إلحاقي لكل تغيير ومن فعله ═══
create table if not exists public.admin_request_events (
  id           bigint generated always as identity primary key,
  request_id   uuid,
  request_type text,
  subject_id   uuid,
  action       text not null,
  actor_id     uuid,
  actor_role   text,
  note         text,
  at           timestamptz not null default clock_timestamp()
);
create index if not exists admin_request_events_request_idx on public.admin_request_events (request_id, at);
create index if not exists admin_request_events_at_idx on public.admin_request_events (at desc);
comment on table public.admin_request_events is
  'ما تم في كل طلب مراجعة ومن فعله (20261111150000) — يكتبه السيرفر وحده من مشغّلَي admin_requests وprofiles';

alter table public.admin_request_events enable row level security;
drop policy if exists admin_request_events_select on public.admin_request_events;
create policy admin_request_events_select on public.admin_request_events for select to authenticated
  using (public.can_handle_admin_request(request_type));
revoke all on public.admin_request_events from public, anon, authenticated;
grant select on public.admin_request_events to authenticated;
grant all on public.admin_request_events to service_role;

create or replace function public.admin_request_log_event(p_request_id uuid, p_type text, p_subject uuid,
                                                          p_action text, p_note text)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  me    uuid := public.current_profile_id();
  maint boolean := coalesce(auth.role() = 'service_role', false) or auth.uid() is null;
  role_ text;
begin
  if me is not null and not exists (select 1 from public.profiles p where p.id = me) then
    me := null;
  end if;
  role_ := case when maint then 'server' else coalesce(public.current_user_role(), 'pending') end;
  insert into public.admin_request_events (request_id, request_type, subject_id, action, actor_id, actor_role, note)
  values (p_request_id, p_type, p_subject, p_action, case when maint then null else me end, role_,
          nullif(left(btrim(coalesce(p_note, '')), 2000), ''));
end;
$function$;
revoke all on function public.admin_request_log_event(uuid, text, uuid, text, text) from public, anon, authenticated;

create or replace function public.trg_admin_request_events()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  n    jsonb;
  o    jsonb;
  act  text;
  note text;
  me   uuid;
begin
  -- to_jsonb: يعمل وإن غابت أعمدة «مسار الموافقات» (قاعدة أقدم)
  if tg_op = 'INSERT' then
    n := to_jsonb(new);
    perform public.admin_request_log_event(new.id, new.request_type, new.member_id, 'sent', null);
    if coalesce(n ->> 'status', 'pending') <> 'pending' then
      -- سجلّ أُدرج مغلقاً (تعديل مباشر من الإدارة)
      perform public.admin_request_log_event(new.id, new.request_type, new.member_id, n ->> 'status', n ->> 'admin_reply');
    end if;
    return new;
  end if;

  if tg_op = 'DELETE' then
    o := to_jsonb(old);
    me := public.current_profile_id();
    perform public.admin_request_log_event(old.id, old.request_type, old.member_id,
      case when me is not null and me = old.requester_id and coalesce(o ->> 'status', '') = 'pending'
           then 'withdrawn' else 'deleted' end,
      'الحالة عند الحذف: ' || coalesce(o ->> 'status', '—'));
    return old;
  end if;

  n := to_jsonb(new);
  o := to_jsonb(old);
  if (n -> 'status') is distinct from (o -> 'status') then
    act := case
      when n ->> 'status' = 'pending' then 'reopened'
      when n ->> 'status' = 'approved' and new.request_type = 'contact_message' then 'replied'
      when n ->> 'status' = 'approved' and o ->> 'stage' = 'execute' then 'executed'
      when n ->> 'status' = 'approved' then 'approved'
      when n ->> 'status' = 'rejected' then 'rejected'
      else 'status:' || coalesce(n ->> 'status', 'null') end;
    note := n ->> 'admin_reply';
  elsif ((n -> 'recommendation') is distinct from (o -> 'recommendation')
         or (n -> 'recommended_at') is distinct from (o -> 'recommended_at')) and n ->> 'recommendation' is not null then
    act := 'recommended_' || (n ->> 'recommendation');
    note := n ->> 'recommendation_note';
  elsif (n -> 'approved_by') is distinct from (o -> 'approved_by') and n ->> 'approved_by' is not null then
    act := 'manager_approved';
    note := n ->> 'approval_note';
  elsif ((n -> 'info_request') is distinct from (o -> 'info_request') or (n -> 'info_fields') is distinct from (o -> 'info_fields'))
        and n ->> 'info_request' is not null and n ->> 'stage' = 'info' then
    act := 'info_requested';
    note := n ->> 'info_request';
  elsif (n -> 'info_reply') is distinct from (o -> 'info_reply') and n -> 'info_reply' is not null
        and jsonb_typeof(n -> 'info_reply') <> 'null' then
    act := 'info_replied';
  elsif (n -> 'stage') is distinct from (o -> 'stage') then
    act := case when n ->> 'stage' = 'review' and o ->> 'stage' in ('approve', 'execute') then 'returned'
                else 'stage:' || coalesce(n ->> 'stage', 'none') end;
    note := n ->> 'approval_note';
  elsif (n -> 'assigned_to') is distinct from (o -> 'assigned_to') then
    act := case when n ->> 'assigned_to' is null then 'released' else 'claimed' end;
  elsif (n -> 'escalated_at') is distinct from (o -> 'escalated_at') and n ->> 'escalated_at' is not null then
    act := 'escalated';
  elsif (n -> 'admin_reply') is distinct from (o -> 'admin_reply') and nullif(btrim(n ->> 'admin_reply'), '') is not null then
    act := 'replied';
    note := n ->> 'admin_reply';
  elsif (new.member_id, new.requester_id) is distinct from (old.member_id, old.requester_id) then
    act := 'moved';
  end if;
  if act is not null then
    perform public.admin_request_log_event(new.id, new.request_type, new.member_id, act, note);
  end if;
  return new;
end;
$function$;
revoke all on function public.trg_admin_request_events() from public, anon, authenticated;

drop trigger if exists trg_zzz_admin_request_events on public.admin_requests;
create trigger trg_zzz_admin_request_events
  after insert or update or delete on public.admin_requests
  for each row execute function public.trg_admin_request_events();

-- قبول الانضمام بتفعيل الحساب: الإدارة ترفع المعلّق (الدور أو الحالة) — مربوطاً بآخر طلب انضمام/ربط له
create or replace function public.trg_profiles_activation_event()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  rid uuid;
  rtype text;
begin
  if not ((old.role is not distinct from 'pending' and new.role is distinct from 'pending')
          or (coalesce(old.status, 'pending') = 'pending' and new.status = 'active')) then
    return new;
  end if;
  -- الإدارة فقط (التفعيل الذاتي عند أول دخول ليس قبولاً)
  if coalesce(public.current_user_role(), '') not in ('owner', 'admin', 'monitor', 'supervisor') then
    return new;
  end if;
  select r.id, r.request_type into rid, rtype from public.admin_requests r
   where (r.member_id = new.id or r.requester_id = new.id) and r.request_type in ('join_request', 'link_request')
   order by r.created_at desc nulls last limit 1;
  perform public.admin_request_log_event(rid, coalesce(rtype, 'join_request'), new.id, 'member_activated',
    case when old.role is distinct from new.role then 'الدور: ' || coalesce(old.role, '—') || ' ← ' || coalesce(new.role, '—') end);
  return new;
end;
$function$;
revoke all on function public.trg_profiles_activation_event() from public, anon, authenticated;

drop trigger if exists trg_zzz_profiles_activation_event on public.profiles;
create trigger trg_zzz_profiles_activation_event
  after update of status, role on public.profiles
  for each row execute function public.trg_profiles_activation_event();
