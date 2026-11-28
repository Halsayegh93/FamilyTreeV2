-- قيود «لم يستكمل التسجيل» (incomplete) و«مقيّد» (limited) على السيرفر — ملاحظة «المنتقد» ٢٠٢٦-١١-٢٨ (البند ١)
-- مطبَّق على الحي ٢٠٢٦-١١-٢٨ بعد تجربة begin…raise exception بجلسات authenticated حقيقية: العضو العادي ecedfa92
-- (family_woman) والمالك 88d7b2f2 والمراقب (6b3e784d مؤقتاً داخل المعاملة) بلا أي فرق قبل/بعد؛ «لم يستكمل» (84e050f8 بعد تفريغ
-- completed_at داخل المعاملة — لا حساب «لم يستكمل» حقيقي اليوم، f20a2fd2 حساب المراجعة يبقى daughter_son) و«مقيّد» 342cf2f6:
-- قبل: الحالة/الصورة/الرقم/إضافة زوجة/ترتيب الأبناء تمرّ — بعد: category_locked؛ last_seen_at وإخفاء الرقم والقراءة كما هي.
--
-- كان member_access_allows يحرس الأخبار/التعليق/الإعجاب/الديوانيات/المشاريع/المكتبة فقط، والملف الشخصي و«عائلتي»
-- مخفيّة في التطبيق فقط. الآن:
--   (أ) public.trg_profiles_category_guard (حارس قبل التعديل/الإضافة على profiles، للكتابة المباشرة من التطبيقات فقط —
--       current_user = authenticated؛ دوال السيرفر SECURITY DEFINER لا تتأثر). صاحب الحساب من الفئتين:
--         • البيانات (الاسم، الميلاد، الحالة الاجتماعية، السيرة، الجنس، الوفاة، اسم العائلة، البريد، اسم المستخدم) ← profile.edit_info
--         • الصورة والغلاف (avatar_url، photo_url، cover_url) ← profile.photo
--         • الرقم (phone_number) ← profile.change_phone
--         • الأم/الزوج، وأي تعديل في سجل غيره، وإضافة سجل (ابن) ← profile.my_family
--       كل ما سواها يمرّ كما هو: last_seen_at، last_active_at، current_screen…، notification_prefs، الخصوصية
--       (is_phone_hidden، is_birth_date_hidden، is_photo_hidden، activity_visible)، badge_enabled، avatar_unavailable،
--       terms_accepted_*، registration_platform، updated_by/updated_at. القيم غير المتغيّرة تمرّ.
--       الخانة تُقرأ من member_access_allows (المصفوفة member_category_access ثم الافتراضي member_category_access_defaults)،
--       فإن فتح المالك الخانة للفئة يمرّ التعديل بلا بناء.
--   (ب) دوال «عائلتي» ترفض للفئتين إن كانت profile.my_family مطفأة: يُحقن سطر واحد في أولها
--       `perform private.assert_my_family_allowed();` (حقن نصّي آمن: كل دالة فيها «begin» واحد في سطر وحده، ويُتخطّى ما حُقن).
--       الدوال: add_family_child، add_or_link_self_relative، add_self_mother، add_self_wife، remove_self_child،
--       remove_self_wife، remove_self_woman_child، reorder_self_children، reorder_self_women_children، set_self_mother،
--       set_self_relative_mother، set_self_wife، set_self_wife_hidden، set_self_woman_hidden، update_self_woman_child.
--       خارجها: set_mother_visibility و women_family_set_visibility (خصوصية الشخص نفسه)، add_outside_husband (للإدارة).
--   الرفض: errcode 42501، hint = category_locked، نصّ عربي.
-- الإدارة (staff) والأعضاء الآخرون: my_member_category ≠ الفئتين ← لا تغيير.
-- التراجع: supabase/rollback/20261128190000_member_category_server_guards_rollback.sql

create or replace function private.category_locked(p_key text)
 returns boolean
 language plpgsql
 stable security definer
 set search_path to ''
as $$
begin
  if coalesce(public.my_member_category(), '') not in ('incomplete', 'limited') then
    return false;
  end if;
  return not public.member_access_allows(p_key);
end;
$$;
revoke all on function private.category_locked(text) from public, anon, authenticated;

create or replace function private.assert_my_family_allowed()
 returns void
 language plpgsql
 stable security definer
 set search_path to ''
as $$
begin
  if private.category_locked('profile.my_family') then
    raise exception 'إضافة الأقارب وتعديلهم غير متاحة لحسابك حتى يكتمل تسجيلك'
      using errcode = '42501', hint = 'category_locked';
  end if;
end;
$$;
revoke all on function private.assert_my_family_allowed() from public, anon, authenticated;

-- دالة الحارس بصلاحية المتصل (لا SECURITY DEFINER — وإلا صار current_user مالك الدالة فلا يُعرف أن الكتابة من التطبيق)،
-- ولا تستدعي إلا دوال public المتاحة لـ authenticated (المخطط private غير متاح له) — مثل trg_profiles_descendant_guard.
create or replace function public.trg_profiles_category_guard()
 returns trigger
 language plpgsql
 set search_path to ''
as $$
declare
  me uuid;
begin
  if current_user <> 'authenticated' then
    return new;
  end if;
  me := public.current_profile_id();
  if me is null or coalesce(public.my_member_category(), '') not in ('incomplete', 'limited') then
    return new;
  end if;

  if tg_op = 'INSERT' or new.id is distinct from me then
    -- إضافة ابن (إدراج مباشر) أو تعديل سجل قريب = «عائلتي»
    if not public.member_access_allows('profile.my_family') then
      raise exception 'إضافة الأقارب وتعديلهم غير متاحة لحسابك حتى يكتمل تسجيلك'
        using errcode = '42501', hint = 'category_locked';
    end if;
    return new;
  end if;

  if (new.first_name, new.full_name, new.birth_date, coalesce(new.is_married, false), new.bio_json, new.bio,
      new.gender, coalesce(new.is_deceased, false), new.death_date, coalesce(new.death_date_unknown, false),
      new.family_name, new.email, new.username)
     is distinct from
     (old.first_name, old.full_name, old.birth_date, coalesce(old.is_married, false), old.bio_json, old.bio,
      old.gender, coalesce(old.is_deceased, false), old.death_date, coalesce(old.death_date_unknown, false),
      old.family_name, old.email, old.username)
     and not public.member_access_allows('profile.edit_info') then
    raise exception 'تعديل البيانات غير متاح لحسابك حتى يكتمل تسجيلك' using errcode = '42501', hint = 'category_locked';
  end if;
  if (new.avatar_url, new.photo_url, new.cover_url) is distinct from (old.avatar_url, old.photo_url, old.cover_url)
     and not public.member_access_allows('profile.photo') then
    raise exception 'تغيير الصورة غير متاح لحسابك حتى يكتمل تسجيلك' using errcode = '42501', hint = 'category_locked';
  end if;
  if new.phone_number is distinct from old.phone_number and not public.member_access_allows('profile.change_phone') then
    raise exception 'تغيير الرقم غير متاح لحسابك حتى يكتمل تسجيلك' using errcode = '42501', hint = 'category_locked';
  end if;
  if (new.mother_id, new.husband_id) is distinct from (old.mother_id, old.husband_id)
     and not public.member_access_allows('profile.my_family') then
    raise exception 'إضافة الأقارب وتعديلهم غير متاحة لحسابك حتى يكتمل تسجيلك' using errcode = '42501', hint = 'category_locked';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_profiles_category_guard on public.profiles;
create trigger trg_profiles_category_guard
  before insert or update on public.profiles
  for each row execute function public.trg_profiles_category_guard();

-- (ب) حقن الحارس في دوال «عائلتي»
do $do$
declare
  fn  text;
  def text;
  n   int;
begin
  foreach fn in array array['add_family_child', 'add_or_link_self_relative', 'add_self_mother', 'add_self_wife',
                            'remove_self_child', 'remove_self_wife', 'remove_self_woman_child', 'reorder_self_children',
                            'reorder_self_women_children', 'set_self_mother', 'set_self_relative_mother', 'set_self_wife',
                            'set_self_wife_hidden', 'set_self_woman_hidden', 'update_self_woman_child'] loop
    select pg_get_functiondef(p.oid) into def
      from pg_proc p join pg_namespace s on s.oid = p.pronamespace
     where s.nspname = 'public' and p.proname = fn;
    if def is null then
      raise exception 'الدالة % غير موجودة', fn;
    end if;
    if position('private.assert_my_family_allowed()' in def) > 0 then
      continue;
    end if;
    select count(*) into n from regexp_matches(def, E'\\nbegin\\n', 'g');
    if n <> 1 then
      raise exception 'الدالة % فيها % سطر begin — الحقن غير آمن', fn, n;
    end if;
    execute regexp_replace(def, E'\\nbegin\\n', E'\nbegin\n  perform private.assert_my_family_allowed();   -- 20261128190000\n');
  end loop;
end;
$do$;
