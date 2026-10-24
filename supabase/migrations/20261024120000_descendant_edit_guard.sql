-- فحص ٢٠٢٦-١٠-٢٤ (خ-١): الأب/الجد يعدّل سجل ابنه/حفيده عبر الـ API مباشرة
-- سياسة profiles_update_self_or_moderator تسمح بـ is_descendant_of_caller(id) بأي عمق، والحارس
-- trg_profiles_protect_sensitive_columns يحمي سجل الشخص نفسه فقط — فكان الأب يقدر يسجّل ابنه البالغ
-- «متوفى» (فيُسحب دوره الإداري تلقائياً)، أو يخفيه، أو يغيّر أباه (حلقة في الشجرة)، أو يعدّل اسمه
-- ورقمه وله حساب دخول.
-- الحارس الجديد للكتابة المباشرة من التطبيقات فقط (current_user = authenticated) — دوال السيرفر
-- (SECURITY DEFINER: الربط أول دخول، تسلسل الأسماء، قرار الطلبات…) لا تتأثر.
-- لغير المالك/المدير/المراقب عند تعديل سجل غيره:
--   • له حساب دخول خاص = يدير سجله بنفسه → أي تغيير مرفوض (hint = descendant_has_account)
--   • الوفاة، الأب، الإخفاء، اسم العائلة، الدور، الحالة → مرفوض (بطلب للإدارة، كما يفعل التطبيق للوفاة)
--   • تاريخ الوفاة → يبقى القديم بصمت (الآيفون يرسل «اليوم» لمتوفى بلا تاريخ — ن-٦)
--   • الاسم، الميلاد، الرقم، الصورة… لابن بلا حساب → كما هي (الأب يدير «عائلتي»)
--   • ترتيب الأبناء (sort_order) مسموح دائماً
-- القيم غير المتغيّرة تمر. التراجع: rollback/20261024120000_descendant_edit_guard_rollback.sql
-- تجربة: cd supabase/tests/family_links && node descendant_edit_guard.test.mjs

create or replace function public.profile_has_login(p_id uuid)
 returns boolean
 language sql
 stable
 security definer
 set search_path to ''
as $$
  select exists (
    select 1 from auth.users u
    where u.id = p_id or u.raw_app_meta_data ->> 'profile_id' = p_id::text);
$$;
revoke all on function public.profile_has_login(uuid) from public, anon;
grant execute on function public.profile_has_login(uuid) to authenticated;

create or replace function public.trg_profiles_descendant_guard()
 returns trigger
 language plpgsql
 security invoker
 set search_path to 'public'
as $function$
declare
  caller_role text;
  cmp public.profiles;
begin
  -- دوال السيرفر تكتب بصلاحية مالكها (postgres) — الحارس للكتابة المباشرة من التطبيقات
  if current_user <> 'authenticated' then
    return new;
  end if;
  if old.id = public.current_profile_id() then
    return new;
  end if;
  caller_role := coalesce(public.current_user_role(), 'anonymous');
  if caller_role in ('owner', 'admin', 'monitor') then
    return new;
  end if;

  if new.is_deceased is distinct from old.is_deceased
     or new.father_id is distinct from old.father_id
     or new.is_hidden_from_tree is distinct from old.is_hidden_from_tree
     or new.family_name is distinct from old.family_name
     or new.role is distinct from old.role
     or new.status is distinct from old.status then
    raise exception 'الوفاة والأب والإخفاء واسم العائلة تتعدل عبر طلب للإدارة'
      using errcode = '42501', hint = 'descendant_edit_forbidden';
  end if;
  new.death_date := old.death_date;

  -- ترتيب الأبناء في «عائلتي» وحقول التتبع لا تُعدّ تعديلاً على السجل
  cmp := new;
  cmp.sort_order := old.sort_order;
  cmp.updated_at := old.updated_at;
  cmp.updated_by := old.updated_by;
  if cmp is distinct from old and public.profile_has_login(old.id) then
    raise exception 'لهذا الشخص حساب في التطبيق — يعدّل بياناته بنفسه أو عبر الإدارة'
      using errcode = '42501', hint = 'descendant_has_account';
  end if;

  return new;
end;
$function$;
revoke all on function public.trg_profiles_descendant_guard() from public, anon;

drop trigger if exists trg_profiles_descendant_guard on public.profiles;
create trigger trg_profiles_descendant_guard before update on public.profiles
  for each row execute function public.trg_profiles_descendant_guard();
