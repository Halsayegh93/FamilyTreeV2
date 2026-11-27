-- مطبَّق على الحي ٢٠٢٦-١١-٢٧ بعد تجربة begin…rollback
-- «صلاحيات الأعضاء حسب الفئة» (طلب المالك ٢٠٢٦-١١-٢٧): «بالادارة في الفريق والامان كل حساب نقدر نعدل على صلاحياته…
-- بشكل عام مو مخصوص… زوج البنت شنو يقدر يشوف، بنت البنت شنو تقدر تشوف»، و«حتى داخل قائمة الشاشات ابى الشاشات الداخلية».
-- NOT APPLIED — يطبّقه المدير بعد تجربة begin…rollback وموافقة المالك. فوق 20261127160000_outside_family_signup (حيّ).
--
--  ١) `app_config.member_category_access` (json): {الفئة: {مفتاح: true|false}} — الفئات family_man · family_woman ·
--     daughter_son · daughter_daughter · limited · outside_spouse، والمفاتيح `private.member_access_keys()` (= `MemberScreen`
--     في Core/MemberAccess.swift). خانة غائبة = الافتراضي = اليوم (كل شيء ظاهر، و«محدود» = outside_member_locked_sections
--     — المفتاح القديم يبقى احتياطاً). القيمة الأولى تطوي القائمة القديمة في صفّ «limited» (لا يتغيّر شيء على أحد).
--     يقرؤها كل مسجّل عبر app_config()، ويعدّلها المالك وحده عبر set_app_config الموجودة.
--  ٢) الفحص `trg_app_config_member_access_guard` (مثل trg_app_config_role_matrix_guard): فئة أو مفتاح غير معروف يُرفض،
--     وقيمة غير true/false، و«حسابي» نفسه، و**أي مفتاح للإبلاغ أو الحظر** (قاعدة المالك «الابلاغ و الحظر اجباري على الكل
--     ظاهر» + شرط Apple) — 22023 bad_value برسالة عربية.
--  ٣) `my_member_category()`: فئة المتصل من حسابه (staff للإدارة، null لغير المفعّل) — التطبيق يقرؤها، فكل عميل يتفق.
--     `member_access_allows(key)`: الخانة وكل أمهاتها ظاهرة لفئته (الإدارة وغير المفعّل نعم، والإبلاغ والحظر نعم دائماً).
--  ٤) الفرض على السيرفر (لا إخفاء في التطبيق وحده):
--     • `lineage_locked(section)` يرجع true حين تُطفأ الشاشة لفئته ← سياسات القراءة الموجودة على الديوانيات والمشاريع
--       والمكتبة (family_archive) وشجرة النساء تمنعها. حالة «استكمال التسجيل» لابن البنت كما هي.
--     • `members_masked.phone_number` = null لغيره حين يُطفأ `member_details.contact` (أو تفاصيل العضو كلها) — الأعمدة
--       وترتيبها وبقية القواعد كما هي حرفياً (20261112100000).
--     • سياسات إدراج RESTRICTIVE: news (news.add) · news_comments (news.comment) · news_likes (news.like) ·
--       news_poll_votes (news.polls) · diwaniyas (diwaniyas.add) · projects (projects.add) · family_archive (library.add).
--       الدوال SECURITY DEFINER والإدارة لا تتأثر.
--  ملاحظة: التطبيقات ما زالت تقرأ `profiles` مباشرة في أماكن (CLAUDE.md «المرحلة الثانية») — الرقم هناك يحرسه إخفاء
--  الرقم الحالي فقط حتى تُسحب قراءة phone_number من profiles.
-- التراجع: rollback/20261127190000_member_category_access_rollback.sql
-- التجربة: cd supabase/tests/family_links && node member_category_access.test.mjs

-- ── ١) القائمة الثابتة ──
create or replace function private.member_access_keys()
returns text[]
language sql
immutable
set search_path to ''
as $function$
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
    'profile.my_family', 'profile.edit_info', 'profile.change_phone', 'profile.qr'];
$function$;

create or replace function private.member_access_categories()
returns text[]
language sql
immutable
set search_path to ''
as $function$
  select array['family_man', 'family_woman', 'daughter_son', 'daughter_daughter', 'limited', 'outside_spouse'];
$function$;

-- الإبلاغ والحظر: أي جزء من المفتاح فيه report أو block
create or replace function private.member_access_protected(p_key text)
returns boolean
language sql
immutable
set search_path to ''
as $function$
  select exists (select 1 from unnest(string_to_array(coalesce(p_key, ''), '.')) part
                  where part like '%report%' or part like '%block%');
$function$;

-- ── ٢) الفحص ──
create or replace function private.member_category_access_problem(p jsonb)
returns text
language plpgsql
immutable
set search_path to ''
as $function$
declare
  v_cat text;
  v_row jsonb;
  v_key text;
  v_val jsonb;
begin
  if p is null or jsonb_typeof(p) <> 'object' then
    return 'الجدول يجب أن يكون كائناً بالفئات';
  end if;
  for v_cat, v_row in select * from jsonb_each(p) loop
    if not (v_cat = any (private.member_access_categories())) then
      return 'فئة غير معروفة: ' || v_cat;
    end if;
    if jsonb_typeof(v_row) <> 'object' then
      return 'صفّ ' || v_cat || ' يجب أن يكون كائناً';
    end if;
    for v_key, v_val in select * from jsonb_each(v_row) loop
      if private.member_access_protected(v_key) then
        return 'الإبلاغ والحظر يظهران للجميع دائماً — لا يدخلان الجدول (' || v_key || ')';
      end if;
      if v_key = 'profile' then
        return '«حسابي» لا يُخفى (حذف الحساب والإعدادات) — ما بداخله فقط';
      end if;
      if not (v_key = any (private.member_access_keys())) then
        return 'شاشة غير معروفة: ' || v_key;
      end if;
      if jsonb_typeof(v_val) <> 'boolean' then
        return 'قيمة ' || v_cat || '.' || v_key || ' يجب أن تكون true أو false';
      end if;
    end loop;
  end loop;
  return null;
end;
$function$;

create or replace function private.app_config_member_access_guard()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare v_msg text;
begin
  v_msg := private.member_category_access_problem(new.default_value);
  if v_msg is not null then
    raise exception 'الافتراضي لـ %: %', new.key, v_msg using errcode = '22023', hint = 'bad_value';
  end if;
  v_msg := private.member_category_access_problem(new.value);
  if v_msg is not null then
    raise exception '%', v_msg using errcode = '22023', hint = 'bad_value';
  end if;
  return new;
end;
$function$;

revoke all on function private.member_access_keys(), private.member_access_categories(),
  private.member_access_protected(text), private.member_category_access_problem(jsonb),
  private.app_config_member_access_guard() from public, anon, authenticated;

drop trigger if exists trg_app_config_member_access_guard on public.app_config;
create trigger trg_app_config_member_access_guard
  before insert or update on public.app_config
  for each row when (new.key = 'member_category_access')
  execute function private.app_config_member_access_guard();

-- القيمة الأولى: القائمة القديمة مطويّة في صفّ «limited» (الافتراضي {} = اليوم، والقديم احتياط)
insert into public.app_config (key, value, default_value, kind, category, label_ar, help_ar, rules, is_public, sort)
select 'member_category_access',
       case when coalesce(jsonb_array_length(folded), 0) = 0 then '{}'::jsonb
            else jsonb_build_object('limited', (select jsonb_object_agg(k, false) from jsonb_array_elements_text(folded) k)) end,
       '{}'::jsonb, 'json', 'members',
       'صلاحيات الأعضاء حسب الفئة',
       'لكل فئة (عضو من العائلة، نساء العائلة، ابن بنت، بنت بنت، عضو بصلاحيات محدودة، زوج أو زوجة من خارج العائلة): الشاشات وما بداخلها، true ظاهر وfalse مخفي. الغائب = الافتراضي (كل شيء ظاهر، والمحدود حسب outside_member_locked_sections). الإبلاغ والحظر ظاهران دائماً ولا يدخلان الجدول. الإدارة ترى كل شيء.',
       '{}'::jsonb, false, 76
  from (select coalesce(
          (select (select jsonb_agg(e) from jsonb_array_elements_text(c.value) e
                    where e = any (private.member_access_keys()))
             from public.app_config c
            where c.key = 'outside_member_locked_sections' and jsonb_typeof(c.value) = 'array'),
          case when exists (select 1 from public.app_config c where c.key = 'outside_member_locked_sections'
                                                               and jsonb_typeof(c.value) = 'array')
               then '[]'::jsonb
               else '["diwaniyas", "projects", "library", "women_tree", "member_details"]'::jsonb end) as folded) f
on conflict (key) do nothing;

-- ── ٣) الفئة والسؤال ──
create or replace function public.my_member_category()
returns text
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_me     uuid := public.current_profile_id();
  v_role   text := coalesce(public.current_user_role(), '');
  v_female boolean;
  v_father uuid;
begin
  if v_me is null then return null; end if;
  if v_role in ('owner', 'admin', 'monitor', 'supervisor') then return 'staff'; end if;
  if v_role <> 'member' then return null; end if;   -- معلّق، موقوف، محذوف: خارج الجدول (حرّاسهم الحالية)
  select lower(btrim(coalesce(p.gender, ''))) = 'female', p.father_id into v_female, v_father
    from public.profiles p where p.id = v_me;
  if exists (select 1 from public.daughter_son_lineage d where d.profile_id = v_me and d.limited_at is not null) then
    return 'limited';
  end if;
  if exists (select 1 from public.daughter_son_lineage d where d.profile_id = v_me)
     or (v_father is null and exists (
           select 1 from public.women_members w
            where (w.id = v_me or w.linked_user_id = v_me) and w.mother_id is not null
              and (w.parent_id is null
                   or exists (select 1 from public.women_members f where f.id = w.parent_id and f.is_outside_family)))) then
    return case when v_female then 'daughter_daughter' else 'daughter_son' end;
  end if;
  if v_father is null and exists (select 1 from public.women_members w
                                   where (w.id = v_me or w.linked_user_id = v_me) and w.is_outside_family) then
    return 'outside_spouse';
  end if;
  return case when v_female then 'family_woman' else 'family_man' end;
end;
$function$;
comment on function public.my_member_category() is
  'Caller''s member category for app_config.member_category_access: staff · family_man · family_woman · daughter_son · daughter_daughter · limited · outside_spouse; null when not an active member.';

create or replace function public.member_access_allows(p_key text)
returns boolean
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_cat    text := public.my_member_category();
  v_row    jsonb;
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
    if v_v is not null and jsonb_typeof(v_v) = 'boolean' then
      if not (v_v #>> '{}')::boolean then return false; end if;
    elsif v_cat = 'limited' and v_legacy ? v_k then
      return false;
    end if;
  end loop;
  return true;
end;
$function$;
comment on function public.member_access_allows(text) is
  'True when the key and all its parents are visible to the caller''s member category (app_config.member_category_access, defaults = today). Staff, non-members and report/block keys: always true.';

revoke all on function public.my_member_category(), public.member_access_allows(text) from public, anon;
grant execute on function public.my_member_category(), public.member_access_allows(text) to authenticated;

-- ── ٤أ) القفل على القراءة ──
create or replace function public.lineage_locked(p_section text)
 returns boolean
 language sql
 stable
 security definer
 set search_path to ''
as $function$
  select case
    when coalesce(public.current_user_role(), '') in ('owner', 'admin', 'monitor', 'supervisor') then false
    -- «صلاحيات الأعضاء حسب الفئة» (20261127190000) — والمحدود منها (outside_member_locked_sections احتياطاً داخلها)
    when not public.member_access_allows(p_section) then true
    when exists (select 1 from public.daughter_son_lineage d
                  where d.profile_id = public.current_profile_id() and d.limited_at is not null) then false
    -- «استكمال التسجيل» لم يُعتمد بعد: daughter_sons_locked_sections (كما كان)
    when exists (select 1 from public.daughter_son_lineage d
                  where d.profile_id = public.current_profile_id() and d.completed_at is null)
      then coalesce((select case when jsonb_typeof(c.value) = 'array' then c.value ? p_section end
                       from public.app_config c where c.key = 'daughter_sons_locked_sections'),
                    p_section = any (array['diwaniyas', 'projects', 'library', 'women_tree', 'member_details']))
    else false
  end;
$function$;
comment on function public.lineage_locked(text) is
  'Section hidden for the caller: member_category_access (incl. limited members, outside_member_locked_sections as fallback), or a daughter''s son/daughter whose «استكمال التسجيل» is not approved yet (daughter_sons_locked_sections). Used by RESTRICTIVE select policies.';

-- ── ٤ب) الرقم في members_masked ──
create or replace view public.members_masked as
with me as materialized (
  select auth.uid()                  as uid,
         public.current_profile_id() as pid,
         public.is_team(auth.uid())  as team,
         public.is_approved_member() as approved,
         -- «الهاتف والاتصال» لفئة المشاهد (20261127190000) — مرة واحدة لكل استعلام
         public.member_access_allows('member_details.contact') as contact_ok
)
select p.id,
       p.first_name,
       p.full_name,
       case when (coalesce(p.is_phone_hidden, false) = false and me.contact_ok) or p.id = me.uid or me.team
            then p.phone_number else null::text end as phone_number,
       case when coalesce(p.is_birth_date_hidden, false) = false or p.id = me.uid or p.id = me.pid or me.team
            then p.birth_date else null::date end as birth_date,
       p.death_date,
       p.is_deceased,
       p.role,
       p.father_id,
       case when coalesce(p.is_photo_hidden, false) = false or p.id = me.uid or p.id = me.pid or me.team
            then p.photo_url else null::text end as photo_url,
       p.is_phone_hidden,
       p.is_hidden_from_tree,
       p.sort_order,
       p.bio_json,
       p.sons_ids,
       p.status,
       p.created_at,
       p.is_married,
       case when coalesce(p.is_photo_hidden, false) = false or p.id = me.uid or p.id = me.pid or me.team
            then p.avatar_url else null::text end as avatar_url,
       p.bio,
       p.is_approved,
       p.is_admin,
       p.is_phone_verified,
       p.is_birth_date_hidden,
       p.cover_url,
       p.badge_enabled,
       p.gender,
       p.updated_by,
       p.updated_at,
       p.is_hr_member,
       p.hr_status,
       case when coalesce(p.activity_visible, true) or p.id = me.uid or p.id = me.pid or me.team
            then p.last_seen_at else null::timestamp with time zone end as last_seen_at,
       case when p.id = me.uid or p.id = me.pid or me.team
            then p.registration_platform else null::text end as registration_platform,
       p.username,
       case when coalesce(p.activity_visible, true) or p.id = me.uid or p.id = me.pid or me.team
            then p.last_active_at else null::timestamp with time zone end as last_active_at,
       case when p.id = me.uid or p.id = me.pid or me.team
            then p.current_screen else null::text end as current_screen,
       case when p.id = me.uid or p.id = me.pid or me.team
            then p.current_screen_source else null::text end as current_screen_source,
       case when p.id = me.uid or me.team
            then p.email else null::text end as email,
       p.mother_id,
       p.husband_id,
       p.terms_accepted_at,
       p.family_name,
       p.death_date_unknown,
       p.avatar_unavailable,
       p.is_photo_hidden,
       p.activity_visible
from public.profiles p
cross join me
where me.uid is not null and (p.id = me.uid or me.approved);
-- ── ٤ج) الإدراج: النشر والتعليق والإعجاب والتصويت والإضافة ──
drop policy if exists news_member_access_insert on public.news;
create policy news_member_access_insert on public.news as restrictive for insert to authenticated
  with check ((select public.member_access_allows('news.add')));
drop policy if exists news_comments_member_access_insert on public.news_comments;
create policy news_comments_member_access_insert on public.news_comments as restrictive for insert to authenticated
  with check ((select public.member_access_allows('news.comment')));
drop policy if exists news_likes_member_access_insert on public.news_likes;
create policy news_likes_member_access_insert on public.news_likes as restrictive for insert to authenticated
  with check ((select public.member_access_allows('news.like')));
drop policy if exists news_poll_votes_member_access_insert on public.news_poll_votes;
create policy news_poll_votes_member_access_insert on public.news_poll_votes as restrictive for insert to authenticated
  with check ((select public.member_access_allows('news.polls')));
drop policy if exists diwaniyas_member_access_insert on public.diwaniyas;
create policy diwaniyas_member_access_insert on public.diwaniyas as restrictive for insert to authenticated
  with check ((select public.member_access_allows('diwaniyas.add')));
drop policy if exists projects_member_access_insert on public.projects;
create policy projects_member_access_insert on public.projects as restrictive for insert to authenticated
  with check ((select public.member_access_allows('projects.add')));
drop policy if exists family_archive_member_access_insert on public.family_archive;
create policy family_archive_member_access_insert on public.family_archive as restrictive for insert to authenticated
  with check ((select public.member_access_allows('library.add')));
