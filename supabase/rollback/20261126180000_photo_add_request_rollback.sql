-- تراجع 20261126180000_photo_add_request — يرجع «طلب تغيير الصورة» كما طُبِّق في 20261111160000 (حرفياً).
-- ١) يوقف مهمة pg_cron 'photo-requests-remind' ويحذف photo_requests_remind_tick وrequest_photo_add_all.
-- ٢) request_photo_change بنصّها السابق حرفياً (السبب مطلوب دائماً، بلا عدّ تذكيرات).
-- ٣) الطلبات المفتوحة بلا سبب (طلبات «أضف صورتك») تأخذ سبباً مقروءاً قبل إرجاع القيد (١–٢٠٠ حرف) — تبقى مفتوحة
--    ويُغلقها المشغّل حين تُضاف الصورة، ومربّع العضو في النسخ القديمة يقرأ «السبب: لا توجد صورة في ملفك».
-- ٤) يسحب قراءة notified_at وreminders_sent من التطبيقات، ويحذف reminders_sent ومفتاحي app_config.
-- الإشعارات المرسلة تبقى في صناديق الأعضاء كنصّ عادي. التطبيق بعده: الزرّ يعرض «تحتاج تحديث السيرفر»، والمربّع يعمل
-- بالأعمدة القديمة (يجرّب الجديدة ثم يرجع للقديمة).

do $do$
begin
  if exists (select 1 from cron.job where jobname = 'photo-requests-remind') then
    perform cron.unschedule('photo-requests-remind');
  end if;
end
$do$;

drop function if exists public.photo_requests_remind_tick();
drop function if exists public.request_photo_add_all();

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

update public.photo_change_requests
   set reason = 'لا توجد صورة في ملفك'
 where char_length(btrim(reason)) = 0;

alter table public.photo_change_requests drop constraint if exists photo_change_requests_reason_len;
alter table public.photo_change_requests
  add constraint photo_change_requests_reason_len check (char_length(btrim(reason)) between 1 and 200);

revoke select (notified_at, reminders_sent) on public.photo_change_requests from authenticated;
alter table public.photo_change_requests drop constraint if exists photo_change_requests_reminders_sent;
alter table public.photo_change_requests drop column if exists reminders_sent;

delete from public.app_config where key in ('photo_request_remind_days', 'photo_request_max_reminders');
