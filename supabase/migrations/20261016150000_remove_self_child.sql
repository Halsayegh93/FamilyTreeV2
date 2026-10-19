-- حذف الابن المضاف بالخطأ من «عائلتي» لكل عضو (طلب المالك ٢٠٢٦-١٠-١٦ «حط زر حذف للكل»)
--
-- كان حذف الابن من «حسابي ← عائلتي ← تعديل بيانات الابن» للمالك والمدير فقط (سياسة الحذف في profiles لهما)،
-- والعضو الذي أضاف ابناً بالخطأ لا يقدر يصلحه. الآن: remove_self_child(p_child_id) — SECURITY DEFINER مقيّدة
-- على أبناء المتصل نفسه (father_id = current_profile_id()) وبحراس:
--   • المتصل مسجّل ومفعّل (عضو، مشرف، مراقب، مدير، مالك) — وإلا hint = not_allowed.
--   • الابن ابنه هو — وإلا hint = not_your_child.
--   • الابن بلا حساب دخول (لا صف في auth.users بمعرّفه ولا حساب منقول إليه app_metadata.profile_id)
--     — وإلا hint = has_account (يحذفه المالك أو المدير).
--   • الابن المتوفى سجلّ نسب — يحذفه المالك أو المدير فقط (ولو كان أباه)، وإلا hint = deceased_protected.
--   • طلب «إضافة ابن» المعلّق عنه (new_value = معرّفه، بأي حالة حروف) يُحذف معه؛ طلباته هو (member_id) تُحذف
--     بالـ CASCADE كما هي.
--   • الحذف نفسه يمر بحراس profiles الحالية كما هي (trg_profiles_protect_delete، وحماية روابط العائلة
--     trg_family_links_protect_delete: من له أبناء/بنات/زوجة مرتبطون لا يُحذف — رسالته العربية تُعاد كما هي
--     مع hint = family_links_protected)، ونسخته في شجرة النساء تُحذف بالمزامنة الحالية.
--   • يُشعَر المالك والمدراء المفعّلون (عدا المتصل): «حذف ابن من الشجرة» — بنوع admin_edit_child_remove
--     (يظهر في «سجل النشاط» بأيقونة «حذف ابن»)، وبنفس أعمدة إشعارات decide_admin_request.
--   • ترجع {deleted: true, id}.
-- التنفيذ للمسجّلين فقط (authenticated) — لا public ولا anon.
--
-- التراجع: supabase/rollback/20261016150000_remove_self_child_rollback.sql (يحذف الدالة — لم تكن موجودة)
-- التجربة: supabase/tests/family_links/remove_self_child.test.mjs

create or replace function public.remove_self_child(p_child_id uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  me       uuid := public.current_profile_id();
  my_role  text := coalesce(public.current_user_role(), '');
  c        public.profiles%rowtype;
  me_first text;
  c_first  text;
  v_msg    text;
  v_hint   text;
begin
  -- المتصل: مسجّل ومفعّل فقط (المعلّق والمجمّد والمحذوف والزائر لا)
  if me is null or my_role not in ('member', 'supervisor', 'monitor', 'admin', 'owner') then
    raise exception 'لا يمكنك حذف الأبناء — حسابك غير مفعّل'
      using errcode = '42501', hint = 'not_allowed';
  end if;

  -- الابن: ابنه هو فقط (قفل الصف حتى نهاية الحذف)
  select * into c from public.profiles where id = p_child_id for update;
  if not found or c.father_id is distinct from me or c.id = me then
    raise exception 'هذا الابن ليس من أبنائك'
      using errcode = '42501', hint = 'not_your_child';
  end if;

  -- له حساب دخول (بمعرّفه، أو حساب نُقل إليه) — ملف عضو حقيقي لا يحذفه الأب
  if exists (select 1 from auth.users u
              where u.id = c.id or (u.raw_app_meta_data ->> 'profile_id') = c.id::text) then
    raise exception 'لهذا الابن حساب دخول — يحذفه المالك أو المدير'
      using errcode = '42501', hint = 'has_account';
  end if;

  -- المتوفى سجلّ نسب — للمالك والمدير فقط
  if coalesce(c.is_deceased, false) and my_role not in ('owner', 'admin') then
    raise exception 'سجل متوفى — يحذفه المالك أو المدير'
      using errcode = '42501', hint = 'deceased_protected';
  end if;

  me_first := coalesce((select nullif(btrim(p.first_name), '') from public.profiles p where p.id = me), 'عضو');
  c_first  := coalesce(nullif(btrim(c.first_name), ''), nullif(split_part(btrim(coalesce(c.full_name, '')), ' ', 1), ''), 'الابن');

  -- طلب «إضافة ابن» المعلّق عنه (الطلب عن الأب، والابن في new_value) — لا يبقى طلب يشير لسجل محذوف
  delete from public.admin_requests
   where request_type = 'child_add'
     and status = 'pending'
     and lower(btrim(coalesce(new_value, ''))) = lower(c.id::text);

  -- الحذف بحراس profiles الحالية؛ رفض حماية الروابط يُعاد برسالته العربية نفسها
  begin
    delete from public.profiles where id = c.id;
  exception when foreign_key_violation then
    get stacked diagnostics v_msg = message_text, v_hint = pg_exception_hint;
    if v_hint = 'family_links_protected' then
      raise exception using message = v_msg, errcode = '23503', hint = 'family_links_protected';
    end if;
    raise;
  end;

  -- إشعار المالك والمدراء المفعّلين (عدا المتصل)
  insert into public.notifications (target_member_id, title, body, kind, created_by)
  select p.id, 'حذف ابن من الشجرة', me_first || ' حذف ابنه «' || c_first || '» من الشجرة',
         'admin_edit_child_remove', me
    from public.profiles p
   where p.role in ('owner', 'admin')
     and p.status = 'active'
     and p.id <> me;

  return jsonb_build_object('deleted', true, 'id', c.id);
end;
$function$;

comment on function public.remove_self_child(uuid) is
  'حذف ابن أضافه العضو بالخطأ من «عائلتي» — أبناؤه هو فقط، بلا حساب دخول، والمتوفى للمالك/المدير؛ hint: not_allowed | not_your_child | has_account | deceased_protected | family_links_protected';

revoke all on function public.remove_self_child(uuid) from public, anon;
grant execute on function public.remove_self_child(uuid) to authenticated;
