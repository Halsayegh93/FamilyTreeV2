-- قيود «لم يستكمل التسجيل» و«مقيّد» (موافقة المالك ٢٠٢٦-١١-٢٨، العيّنة spouse2.html القسم ٢ «نفّذ كل شي»)
-- مطبَّق على الحي ٢٠٢٦-١١-٢٨ بعد تجربة begin…rollback بجلسة authenticated (خانات «لم يستكمل» و«مقيّد» كما في العيّنة،
-- الإبلاغ ظاهر، المالك خارج الجدول، الحارس يرفض «حسابي» في الافتراضي، والعضو يقرأ الافتراضي من app_config()).
-- قبل التطبيق كانت القيمة الحية لـ«لم يستكمل»: library/projects/diwaniyas/women_tree/member_details/news.add/news.like/news.comment/
-- profile.qr/profile.my_family/profile.change_phone = false و profile.edit_info = true، ولـ«مقيّد» الخمسة القديمة = false.
--
-- الافتراضي صار على السيرفر لا في التطبيق: مفتاح جديد app_config.member_category_access_defaults = {فئة: {مفتاح: bool}}
-- يقرؤه member_access_allows والتطبيقات (app_config()) حين لا يذكر member_category_access الخانة. «إعادة الافتراضي» في صفحة
-- «صلاحيات الأعضاء» تحذف صفّ الفئة فيرجع لهذا الافتراضي.
--   incomplete (لم يستكمل) و limited (مقيّد): بلا شجرة النساء، بلا بطاقة تفاصيل الأعضاء، بلا التعليق والإعجاب والنشر
--   (خبر/ديوانية/مشروع/مكتبة)، والملف الشخصي للعرض فقط (بلا تعديل، عائلتي، طلباتي، الصورة، تغيير الرقم، رمز العضو).
--   limited يزيد: بلا شجرة العائلة ولا الديوانيات ولا المكتبة والمشاريع.
--   يبقى للاثنين: الرئيسية والأخبار، الإعدادات، التواصل مع الإدارة، الخروج، حذف الحساب (خارج الجدول أصلاً).
-- مفتاحان جديدان في القائمة: profile.my_requests («الطلبات المرسلة»)، profile.photo (الصورة الشخصية).
-- صفّا الفئتين في القيمة الحية يُنظَّفان من هذه الخانات فيسري الافتراضي الجديد (بقية خانات المالك كما هي).
-- daughter_sons_locked_sections (القفل القديم لـ«لم يستكمل» في lineage_locked) = شجرة النساء وتفاصيل الأعضاء فقط، فالديوانيات
-- والمكتبة والمشاريع تُفتح لمن لم يستكمل كما في العيّنة.

create or replace function private.member_access_keys()
 returns text[]
 language sql
 immutable
 set search_path to ''
as $$
  select array[
    'news', 'news.add', 'news.comment', 'news.like', 'news.polls',
    'tree', 'tree.search', 'tree.my_location', 'tree.kinship',
    'women_tree', 'women_tree.details', 'women_tree.edit_request',
    'member_details', 'member_details.edit_request', 'member_details.kinship', 'member_details.contact',
    'member_details.my_requests', 'member_details.family',
    'diwaniyas', 'diwaniyas.add',
    'projects', 'projects.add',
    'library', 'library.add',
    'contact',
    'notifications',
    'profile.my_family', 'profile.edit_info', 'profile.change_phone', 'profile.qr',
    'profile.my_requests', 'profile.photo'];
$$;

insert into public.app_config (key, value, default_value, kind, category, label_ar, help_ar, is_public, sort)
values ('member_category_access_defaults',
        '{"incomplete": {"women_tree": false, "member_details": false, "news.add": false, "news.comment": false, "news.like": false,
                         "diwaniyas.add": false, "projects.add": false, "library.add": false,
                         "profile.edit_info": false, "profile.my_family": false, "profile.my_requests": false,
                         "profile.photo": false, "profile.change_phone": false, "profile.qr": false},
          "limited":    {"tree": false, "diwaniyas": false, "projects": false, "library": false,
                         "women_tree": false, "member_details": false, "news.add": false, "news.comment": false, "news.like": false,
                         "diwaniyas.add": false, "projects.add": false, "library.add": false,
                         "profile.edit_info": false, "profile.my_family": false, "profile.my_requests": false,
                         "profile.photo": false, "profile.change_phone": false, "profile.qr": false}}'::jsonb,
        '{"incomplete": {"women_tree": false, "member_details": false, "news.add": false, "news.comment": false, "news.like": false,
                         "diwaniyas.add": false, "projects.add": false, "library.add": false,
                         "profile.edit_info": false, "profile.my_family": false, "profile.my_requests": false,
                         "profile.photo": false, "profile.change_phone": false, "profile.qr": false},
          "limited":    {"tree": false, "diwaniyas": false, "projects": false, "library": false,
                         "women_tree": false, "member_details": false, "news.add": false, "news.comment": false, "news.like": false,
                         "diwaniyas.add": false, "projects.add": false, "library.add": false,
                         "profile.edit_info": false, "profile.my_family": false, "profile.my_requests": false,
                         "profile.photo": false, "profile.change_phone": false, "profile.qr": false}}'::jsonb,
        'json', 'members', 'الافتراضي لصلاحيات الأعضاء حسب الفئة',
        'ما تراه كل فئة حين لا تذكر «صلاحيات الأعضاء حسب الفئة» الخانة. الغائب هنا = ظاهر.', false, 76)
on conflict (key) do update set value = excluded.value, default_value = excluded.default_value,
                                label_ar = excluded.label_ar, help_ar = excluded.help_ar;

drop trigger if exists trg_app_config_member_access_guard on public.app_config;
create trigger trg_app_config_member_access_guard
  before insert or update on public.app_config
  for each row when (new.key in ('member_category_access', 'member_category_access_defaults'))
  execute function private.app_config_member_access_guard();

create or replace function public.member_access_allows(p_key text)
 returns boolean
 language plpgsql
 stable security definer
 set search_path to ''
as $$
declare
  v_cat    text := public.my_member_category();
  v_row    jsonb;
  v_def    jsonb;
  v_legacy jsonb;
  v_parts  text[];
  v_k      text;
  v_v      jsonb;
  i        integer;
begin
  if v_cat is null or v_cat = 'staff' or p_key is null then return true; end if;
  if private.member_access_protected(p_key) then return true; end if;   -- الإبلاغ والحظر دائماً
  select c.value -> v_cat into v_row from public.app_config c where c.key = 'member_category_access';
  if v_row is not null and jsonb_typeof(v_row) <> 'object' then v_row := null; end if;
  -- الافتراضي على السيرفر (20261128151000)
  select c.value -> v_cat into v_def from public.app_config c where c.key = 'member_category_access_defaults';
  if v_def is not null and jsonb_typeof(v_def) <> 'object' then v_def := null; end if;
  if v_cat = 'limited' then
    select c.value into v_legacy from public.app_config c where c.key = 'outside_member_locked_sections';
    if v_legacy is null or jsonb_typeof(v_legacy) <> 'array' then
      v_legacy := '["diwaniyas", "projects", "library", "women_tree", "member_details"]'::jsonb;
    end if;
  end if;
  v_parts := string_to_array(p_key, '.');
  for i in 1 .. coalesce(array_length(v_parts, 1), 0) loop
    v_k := array_to_string(v_parts[1:i], '.');
    if v_k = 'profile' then continue; end if;   -- «حسابي» نفسه لا يُخفى
    v_v := v_row -> v_k;
    if v_v is null or jsonb_typeof(v_v) <> 'boolean' then v_v := v_def -> v_k; end if;
    if v_v is not null and jsonb_typeof(v_v) = 'boolean' then
      if not (v_v #>> '{}')::boolean then return false; end if;
    elsif v_cat = 'limited' and v_legacy ? v_k then
      return false;
    end if;
  end loop;
  return true;
end;
$$;

-- القيمة الحية: صفّا الفئتين بلا الخانات التي صار لها افتراض (فيسري) — بقية خانات المالك كما هي
update public.app_config c
   set value = (select coalesce(jsonb_object_agg(e.key,
                  case when e.key in ('incomplete', 'limited')
                       then e.value - array['tree', 'diwaniyas', 'projects', 'library', 'women_tree', 'member_details',
                                            'news.add', 'news.comment', 'news.like', 'diwaniyas.add', 'projects.add', 'library.add',
                                            'profile.edit_info', 'profile.my_family', 'profile.my_requests', 'profile.photo',
                                            'profile.change_phone', 'profile.qr']
                       else e.value end), '{}'::jsonb)
                  from jsonb_each(c.value) e)
 where c.key = 'member_category_access' and jsonb_typeof(c.value) = 'object';
-- صفّ فارغ = بلا تخصيص
update public.app_config c
   set value = (select coalesce(jsonb_object_agg(e.key, e.value), '{}'::jsonb) from jsonb_each(c.value) e
                 where not (jsonb_typeof(e.value) = 'object' and e.value = '{}'::jsonb))
 where c.key = 'member_category_access' and jsonb_typeof(c.value) = 'object';

update public.app_config
   set value = '["women_tree", "member_details"]'::jsonb, default_value = '["women_tree", "member_details"]'::jsonb
 where key = 'daughter_sons_locked_sections';
