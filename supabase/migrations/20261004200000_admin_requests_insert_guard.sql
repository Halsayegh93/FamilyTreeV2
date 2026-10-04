-- طلبات المراجعة: السيرفر يرفض الطلب المفبرك (فحص الثغرات ٢٠٢٦-١٠-٠٤، البند أ-٣)
--
-- كانت الكتابة في admin_requests مشروطة بـ requester_id = auth.uid() فقط، والموافقة/الرفض
-- في التطبيقات تنفّذ ما كتبه مقدّم الطلب: تعديل الشجرة يكتب على details.targetMemberId
-- بينما المدير يرى الاسم المكتوب في الطلب، ورفض «إضافة ابن» يحذف الملف المذكور في
-- new_value، وقبول أي بلاغ يحذف الخبر new_value. فعضو يكتب الطلب بنفسه (بلا التطبيق) يقدر
-- يغيّر رقم مدير أو يحذف ملفاً أو خبراً بموافقة مدير مخدوع.
--
-- حارس قبل الإدراج فقط (التعديل للإدارة وحدها، والدمج/الربط يعدّلون الصفوف) يطابق ما
-- ترسله التطبيقات الحالية والقديمة (آيفون، أندرويد؛ الموقع لا يُدرج):
--   • الإدارة (مالك/مدير/مراقب/مشرف) والسيرفر وصيانة SQL خارج الحارس، كسياسة الإدراج.
--   • الحالة «معلّق» ورد الإدارة فارغ ووقت الإنشاء من السيرفر.
--   • الأنواع الحية فقط (لا مصدر حي لـ deceased_report/photo_suggestion/join_request/edit_request).
--   • مقدّم الطلب هو المتصل، والطلب عن نفسه في كل الأنواع عدا تعديل الشجرة.
--   • غير المفعّل (معلّق/مجمّد) يرسل طلب الانضمام ورسالة التواصل فقط.
--   • تعديل الشجرة: JSON بإجراء معروف، المستهدف/الأب = member_id (مقارنة uuid لأن الآيفون
--     يرسل حروفاً كبيرة)، الصورة من مسار رفع مقدّم الطلب، «طلب آخر» عن نفسه بسبب profile_*،
--     والأسماء المعروضة للمدير تُكتب من السيرفر (لا من الطلب).
--   • «إضافة ابن»: ملف ابن أضافه مقدّم الطلب للتو (أب = هو، خلال ساعة، بلا حساب دخول).
--   • البلاغ عن محتوى لا يشير إلى خبر (قبوله يحذف new_value من الأخبار).
-- التراجع: supabase/rollback/20261004200000_admin_requests_insert_guard_rollback.sql
-- التجربة: supabase/tests/family_links/admin_requests_guard.test.mjs

create or replace function public.guard_admin_request_insert()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  me          uuid := auth.uid();
  my_profile  uuid := public.current_profile_id();
  caller_role text;
  d           jsonb;
  act         text;
  tgt         text;
  par         text;
  member_name text;
  child       record;
  uuid_re     constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
begin
  -- السيرفر وصيانة SQL (مثل حارس الأدوار prevent_role_self_promotion).
  if auth.role() = 'service_role'
     or (auth.role() is null and session_user in ('postgres','supabase_admin','supabase_auth_admin')) then
    return new;
  end if;
  -- بلا دخول: سياسات الجدول ترفضه.
  if me is null then
    return new;
  end if;
  caller_role := coalesce(public.current_user_role(), 'pending');
  if caller_role in ('owner','admin','monitor','supervisor') then
    return new;
  end if;

  new.status      := 'pending';
  new.admin_reply := null;
  new.replied_at  := null;
  new.replied_by  := null;
  new.created_at  := now();

  if new.request_type is null or new.request_type not in (
       'link_request','contact_message','tree_edit','name_change','family_change',
       'phone_change','child_add','news_report','content_report') then
    raise exception 'admin_request_type_not_allowed' using errcode = '42501';
  end if;
  if new.requester_id is null
     or (new.requester_id is distinct from me and new.requester_id is distinct from my_profile) then
    raise exception 'admin_request_requester_not_self' using errcode = '42501';
  end if;
  if new.member_id is null then
    raise exception 'admin_request_member_required' using errcode = '42501';
  end if;
  if new.request_type not in ('link_request','contact_message') and not public.is_approved_member() then
    raise exception 'admin_request_requires_active_member' using errcode = '42501';
  end if;
  if new.request_type <> 'tree_edit' and new.member_id <> new.requester_id then
    raise exception 'admin_request_not_about_self' using errcode = '42501';
  end if;

  -- رفض «إضافة ابن» يحذف الملف new_value: ابن جديد لمقدّم الطلب فقط.
  if new.request_type = 'child_add' then
    if coalesce(new.new_value, '') !~ uuid_re then
      raise exception 'admin_request_child_invalid' using errcode = '42501';
    end if;
    select p.id, p.father_id, p.created_at, p.role into child
    from public.profiles p where p.id = new.new_value::uuid;
    if not found
       or child.father_id is distinct from new.member_id
       or child.created_at is null or child.created_at < now() - interval '1 hour'
       or coalesce(child.role, '') in ('owner','admin','monitor','supervisor')
       or exists (select 1 from auth.users u where u.id = child.id)
       or exists (select 1 from public.admin_requests r
                  where r.request_type = 'child_add' and lower(r.new_value) = lower(new.new_value)) then
      raise exception 'admin_request_child_invalid' using errcode = '42501';
    end if;
  end if;

  -- قبول أي بلاغ يحذف الخبر new_value: البلاغ عن محتوى لا يشير إلى خبر.
  if new.request_type = 'content_report' and coalesce(new.new_value, '') ~ uuid_re
     and exists (select 1 from public.news n where n.id = new.new_value::uuid) then
    raise exception 'admin_request_report_targets_news' using errcode = '42501';
  end if;

  if new.request_type = 'tree_edit' then
    begin
      d := new.details::jsonb;
    exception when others then
      d := null;
    end;
    if d is null or jsonb_typeof(d) <> 'object' then
      raise exception 'admin_request_tree_edit_invalid' using errcode = '42501';
    end if;
    act := d->>'action';
    -- القديمة (قبل ٢٠٢٦-٠٥-١١) بأسماء عربية: إضافة / تعديل اسم / حذف.
    if act is null or act not in ('add','edit_name','edit_phone','edit_birth','deceased',
         'add_death_date','add_photo','delete','other','إضافة','تعديل اسم','حذف') then
      raise exception 'admin_request_tree_edit_invalid' using errcode = '42501';
    end if;
    new.new_value := act;

    -- الموافقة تكتب على targetMemberId (والإضافة تحت parentMemberId): لازم = member_id.
    tgt := d->>'targetMemberId';
    par := d->>'parentMemberId';
    if (tgt is not null and (tgt !~ uuid_re or tgt::uuid <> new.member_id))
       or (par is not null and (par !~ uuid_re or par::uuid <> new.member_id))
       or (act in ('add','إضافة') and par is null)
       or (act not in ('add','إضافة') and tgt is null) then
      raise exception 'admin_request_tree_edit_target_mismatch' using errcode = '42501';
    end if;

    if act = 'add_photo' and coalesce(d->>'newPhotoUrl', '') !~* (
         '^https://poxyxsgvzwmnmewytsiw\.supabase\.co/storage/v1/object/public/avatars/photo_suggestion_'
         || new.requester_id::text || '_[0-9a-f-]{36}\.jpg$') then
      raise exception 'admin_request_tree_edit_photo_invalid' using errcode = '42501';
    end if;

    -- «طلب آخر» يأتي فقط من تعديل العضو لملفه بعد تجاوز الحد.
    if act = 'other' and (coalesce(d->>'reason', '') not in ('profile_marital','profile_bio','profile_phone_hidden')
                          or new.member_id <> new.requester_id) then
      raise exception 'admin_request_tree_edit_invalid' using errcode = '42501';
    end if;

    -- «تعديل مباشر من الإدارة» لا يكتبه عضو، والأسماء من السيرفر.
    d := d - 'isAdminDirectEdit';
    select p.full_name into member_name from public.profiles p where p.id = new.member_id;
    if tgt is not null then
      d := case when member_name is null then d - 'targetMemberName'
                else jsonb_set(d, '{targetMemberName}', to_jsonb(member_name)) end;
    end if;
    if par is not null then
      d := case when member_name is null then d - 'parentMemberName'
                else jsonb_set(d, '{parentMemberName}', to_jsonb(member_name)) end;
    end if;
    new.details := d::text;
  end if;

  return new;
end;
$function$;

revoke all on function public.guard_admin_request_insert() from public, anon, authenticated;

drop trigger if exists trg_guard_admin_request_insert on public.admin_requests;
create trigger trg_guard_admin_request_insert
  before insert on public.admin_requests
  for each row execute function public.guard_admin_request_insert();
