-- «طلب تغيير الصورة» (طلب المالك ٢٠٢٦-١١-١١، ميزة معتمدة):
-- NOT APPLIED — يُطبَّق بموافقة المالك. التطبيقات تعمل قبله (بلا زرّ يعمل وبلا مربّع للعضو، بلا أعطال).
--
-- المالك/المدير/المراقب (= canEditMembers) يطلب من عضو له حساب دخول تغيير صورته الشخصية بسبب، مع خيار
-- إخفاء الصورة الحالية حتى يغيّرها. العضو يرى مربّعاً عند فتح التطبيق حتى يغيّرها.
--
-- ١) جدول public.photo_change_requests (سجلّ كامل — كل طلب صفّ، والمفتوح واحد لكل عضو):
--    member_id · reason (١–٢٠٠ حرف) · hide_photo (طلب الإخفاء) · hid_photo (الطلب نفسه أخفاها — كانت ظاهرة)
--    · requested_by · requested_at · notified_at (آخر إشعار) · resolved_at · resolution (photo_changed | cancelled)
--    · resolved_by. فهرس فريد جزئي: طلب مفتوح واحد لكل عضو.
-- ٢) request_photo_change(p_member, p_reason, p_hide default false) → uuid — SECURITY DEFINER:
--    المتصل owner/admin/monitor (current_user_role()؛ المجمّد يفقدها) وإلا 42501 hint = not_allowed؛
--    المالك لا يطلبه منه إلا مالك (owner_protected)؛ ليس لنفسه (own_profile)؛ العضو موجود (member_not_found)،
--    حيّ (deceased)، له حساب دخول profile_has_login (no_account)؛ السبب مطلوب ≤ ٢٠٠ (bad_reason).
--    طلب مفتوح موجود → يُحدَّث (السبب، من طلب، الوقت) ويُرجَع نفس المعرّف — لا طلب ثانٍ.
--    إشعار واحد للعضو (notifications، kind = photo_change_request → مُطلِق الدفع يرسله، فئة admin_activity):
--      «طلب تغيير الصورة الشخصية» / «يرجى تغيير صورتك الشخصية — السبب: <السبب>.»؛ details.photo_change_request_id.
--      تكرار الطلب خلال دقيقة من آخر إشعار يحدّث السبب بلا إشعار جديد (منع الإزعاج)، وبعدها إشعار تذكير جديد.
--    p_hide: الصورة ظاهرة → is_photo_hidden = true (نفس مفتاح خصوصية العضو؛ يراها هو والطاقم فقط عبر members_masked)
--      ويُسجَّل hid_photo. أخفاها العضو بنفسه قبلُ → تبقى، ولا يُظهرها الحلّ لاحقاً (اختياره).
--      فحص الحراس الحالية (٢٠٢٦-١١-١١): trg_profiles_protect_sensitive_columns لا يحرس is_photo_hidden،
--      وtrg_profiles_descendant_guard يمرّر المالك/المدير/المراقب — فالإدارة تقدر عليه مباشرة أيضاً؛ وضع داخل
--      الدالة لتكون العملية ذرّية مع الطلب والإشعار.
-- ٣) cancel_photo_change(p_member) → boolean (نفس الأدوار): يغلق المفتوح (cancelled) ويُظهر الصورة إن أخفاها الطلب.
--    لا مفتوح → false. الإشعار المرسل يبقى (لا حذف بيانات)؛ التطبيق لا يعرض المربّع لطلب غير مفتوح.
-- ٤) trg_zzzz_photo_change_resolve (BEFORE UPDATE OF avatar_url, photo_url على profiles — آخر مشغّلات BEFORE
--    أبجدياً بعد trg_zzz_family_links_guard، فلا يسبق قرار الحراس): صورة جديدة غير فارغة لعضو له طلب مفتوح
--    → resolved_at = now()، resolution = photo_changed، resolved_by = من غيّرها (العضو نفسه، أو الإدارة عند
--    اعتماد صورته المقترحة عبر decide_admin_request، أو الإدارة إن رفعت له صورة)، ويُظهر الصورة إن أخفاها الطلب.
--    حذف الصورة (قيمة فارغة) لا يغلق الطلب. التعديل بلا مستخدم (SQL صيانة، مفتاح الخدمة، إعادة كتابة الروابط)
--    لا يغلقه. إشعار «تعديل بيانات» للإدارة يبقى من notify_member_change كما هو (is_photo_hidden غير متابَع).
-- ٥) RLS: الطاقم (owner/admin/monitor) يقرأ الكل، والعضو يقرأ طلبه المفتوح فقط. القراءة بأعمدة محددة:
--    id, member_id, reason, hide_photo, requested_at, resolved_at, resolution — requested_by/resolved_by/hid_photo/
--    notified_at لا تُقرأ من التطبيقات (الأعضاء يرون «الإدارة» لا الاسم — قاعدة الإشعارات). لا كتابة مباشرة لأحد.
--
-- التراجع: rollback/20261111160000_photo_change_request_rollback.sql
-- تجربة: cd supabase/tests/family_links && node photo_change_request.test.mjs

create table if not exists public.photo_change_requests (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null,
  hide_photo boolean not null default false,
  hid_photo boolean not null default false,
  requested_by uuid references public.profiles(id) on delete set null,
  requested_at timestamptz not null default now(),
  notified_at timestamptz,
  resolved_at timestamptz,
  resolution text,
  resolved_by uuid references public.profiles(id) on delete set null,
  constraint photo_change_requests_reason_len check (char_length(btrim(reason)) between 1 and 200),
  constraint photo_change_requests_resolution check (
    (resolved_at is null and resolution is null)
    or (resolved_at is not null and resolution in ('photo_changed', 'cancelled')))
);

comment on table public.photo_change_requests is
  'طلب تغيير الصورة الشخصية من الإدارة (٢٠٢٦-١١-١١). الكتابة عبر request_photo_change/cancel_photo_change والمشغّل فقط.';

create unique index if not exists photo_change_requests_one_open
  on public.photo_change_requests (member_id) where resolved_at is null;
create index if not exists photo_change_requests_member
  on public.photo_change_requests (member_id, requested_at desc);

alter table public.photo_change_requests enable row level security;

revoke all on public.photo_change_requests from public, anon, authenticated;
grant select (id, member_id, reason, hide_photo, requested_at, resolved_at, resolution)
  on public.photo_change_requests to authenticated;

drop policy if exists photo_change_requests_staff_select on public.photo_change_requests;
create policy photo_change_requests_staff_select on public.photo_change_requests
  for select to authenticated
  using (public.current_user_role() in ('owner', 'admin', 'monitor'));

drop policy if exists photo_change_requests_own_open_select on public.photo_change_requests;
create policy photo_change_requests_own_open_select on public.photo_change_requests
  for select to authenticated
  using (member_id = public.current_profile_id() and resolved_at is null);

-- ─── الطلب ───
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
begin
  if v_me is null or v_role not in ('owner', 'admin', 'monitor') then
    raise exception 'طلب تغيير الصورة للمالك والمدير والمراقب فقط'
      using errcode = '42501', hint = 'not_allowed';
  end if;
  if char_length(v_reason) = 0 or char_length(v_reason) > 200 then
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
           notified_at = case when v_notify then now() else notified_at end
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
            'طلب تغيير الصورة الشخصية',
            'يرجى تغيير صورتك الشخصية — السبب: ' || rtrim(v_reason, '.۔。 ') || '.',
            'photo_change_request', v_me, false,
            jsonb_build_object('photo_change_request_id', v_req.id, 'reason', v_reason),
            p_member);
  end if;

  return v_req.id;
end;
$function$;

revoke all on function public.request_photo_change(uuid, text, boolean) from public, anon;
grant execute on function public.request_photo_change(uuid, text, boolean) to authenticated;

-- ─── الإلغاء ───
create or replace function public.cancel_photo_change(p_member uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_me uuid := public.current_profile_id();
  v_role text := coalesce(public.current_user_role(), 'anonymous');
  v_req public.photo_change_requests%rowtype;
begin
  if v_me is null or v_role not in ('owner', 'admin', 'monitor') then
    raise exception 'إلغاء طلب تغيير الصورة للمالك والمدير والمراقب فقط'
      using errcode = '42501', hint = 'not_allowed';
  end if;
  perform 1 from public.profiles where id = p_member for update;
  select * into v_req from public.photo_change_requests
   where member_id = p_member and resolved_at is null
   for update;
  if not found then
    return false;
  end if;
  update public.photo_change_requests
     set resolved_at = now(), resolution = 'cancelled', resolved_by = v_me
   where id = v_req.id;
  if v_req.hid_photo then
    update public.profiles set is_photo_hidden = false where id = p_member and is_photo_hidden;
  end if;
  return true;
end;
$function$;

revoke all on function public.cancel_photo_change(uuid) from public, anon;
grant execute on function public.cancel_photo_change(uuid) to authenticated;

-- ─── الحلّ عند تغيير الصورة ───
create or replace function public.trg_photo_change_resolve()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := public.current_profile_id();
  v_req public.photo_change_requests%rowtype;
begin
  -- بلا مستخدم (صيانة SQL، مفتاح الخدمة، إعادة كتابة روابط المستودع) — ليس تغييراً للصورة
  if v_actor is null then
    return new;
  end if;
  -- صورة جديدة غير فارغة فقط (الحذف لا يحلّ الطلب)
  if not ((new.avatar_url is distinct from old.avatar_url and nullif(btrim(coalesce(new.avatar_url, '')), '') is not null)
       or (new.photo_url is distinct from old.photo_url and nullif(btrim(coalesce(new.photo_url, '')), '') is not null)) then
    return new;
  end if;
  update public.photo_change_requests
     set resolved_at = now(), resolution = 'photo_changed', resolved_by = v_actor
   where member_id = new.id and resolved_at is null
   returning * into v_req;
  if found and v_req.hid_photo then
    new.is_photo_hidden := false;
  end if;
  return new;
end;
$function$;

revoke all on function public.trg_photo_change_resolve() from public, anon, authenticated;

drop trigger if exists trg_zzzz_photo_change_resolve on public.profiles;
create trigger trg_zzzz_photo_change_resolve
  before update of avatar_url, photo_url on public.profiles
  for each row
  when (new.avatar_url is distinct from old.avatar_url or new.photo_url is distinct from old.photo_url)
  execute function public.trg_photo_change_resolve();
