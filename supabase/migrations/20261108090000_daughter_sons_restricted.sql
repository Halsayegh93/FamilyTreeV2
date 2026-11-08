-- «أكمل حسابك» — الحساب المقيّد لابن البنت من خارج العائلة (طلب المالك ٢٠٢٦-١١-٠٧، فوق 20261107120000_daughter_sons_lineage)
-- APPLIED 2026-11-08 بموافقة المالك. التطبيقات تعمل قبله (القفل من التطبيق، والبحث والإرسال بالمسار القديم).
--
-- كلام المالك: «نبي يكون مقيد الحساب … ما يشوف الديوانيات و ما يشوف المشاريع و المكتبة وشجرة النساء و ما يشوف تفاصيل العضو
-- … اسمه اكمل حسابك … وما ابى يكون باقي تكمل نسبك، ابيه يكون اكمل حسابك».
--
--  ٠) الإعدادات (قاعدة المالك: على السيرفر): daughter_sons_locked_sections (الأقسام المقفولة)، daughter_sons_mother_min_parts
--     (لا نتائج بحث قبل الاسم الثلاثي — للخصوصية)، daughter_sons_father_min_words (أقل كلمات «اسم الأب الكامل»)؛
--     «نسبك» ← «أكمل حسابك» في عناوين الإعدادات وشرحها.
--  ١) نصوص الإشعارات من daughter_sons_texts (notify_*) وافتراضها بصيغة «أكمل حسابك».
--  ٢) القفل على السيرفر: lineage_locked(section) + سياسات RESTRICTIVE للقراءة على diwaniyas · projects · family_archive
--     (المكتبة) · women_members (شجرة النساء). «تفاصيل العضو» يقفلها التطبيق (الشجرة نفسها ظاهرة له).
--  ٣) البحث بلا تصفّح: search_daughters_for_lineage(p_query) — بنات العائلة، و search_men_for_lineage(p_query) — رجال
--     الشجرة (أبو «الأم الجديدة»)؛ لا شيء قبل الحد الأدنى من الكلمات المتتالية من الاسم الأول، و١٠ نتائج بحد أقصى.
--  ٤) submit_daughter_son_lineage: «اسم الأب الكامل» سطراً واحداً (p_father_full_name) + «ما لقيت أمي؟»
--     (p_new_mother_name + p_new_mother_father_id + p_new_mother_deceased). الحقول الأربعة القديمة مقبولة (النسخ القديمة).
--  ٥) decide_lineage_request: «أم جديدة» تُنشأ بنتاً لعقدة أبيها في شجرة النساء (نفس المعرّف — نسخة شجرة الرجال؛ تُنشأ إن
--     غابت)، ثم زوج من خارج العائلة، ثم عقدة الابن — في معاملة واحدة. لا فكّ لأي رابط.
--
-- الهوية من current_profile_id() فقط. الدوال الجديدة SECURITY DEFINER. لا يمسّ غير المُعلَّمين: lineage_locked = false لهم.
-- التراجع: rollback/20261108090000_daughter_sons_restricted_rollback.sql (يُرجَع قبل تراجع 20261107120000)
-- تجربة: cd supabase/tests/family_links && node daughter_sons_restricted.test.mjs

-- ── ٠) الإعدادات ──
insert into public.app_config (key, value, default_value, kind, category, label_ar, help_ar, is_public, sort, min_value, max_value)
values
  ('daughter_sons_locked_sections',
   '["diwaniyas", "projects", "library", "women_tree", "member_details"]'::jsonb,
   '["diwaniyas", "projects", "library", "women_tree", "member_details"]'::jsonb, 'json', 'tree',
   'الأقسام المقفولة قبل «أكمل حسابك»',
   'ما يُقفل على ابن البنت حتى توافق الإدارة على بياناته: diwaniyas (الديوانيات) · projects (المشاريع) · library (المكتبة) · women_tree (شجرة النساء) · member_details (تفاصيل العضو). [] = لا قفل. السيرفر يمنع قراءة الأربعة الأولى، والتطبيق يقفل الخمسة.',
   false, 71, null, null),
  ('daughter_sons_mother_min_parts', '3'::jsonb, '3'::jsonb, 'int', 'tree',
   'أقل عدد أسماء قبل نتائج البحث في «أكمل حسابك»',
   'للخصوصية: لا تظهر أي بنت (ولا رجل في «ما لقيت أمي؟») قبل أن يكتب هذا العدد من الأسماء المتتالية من الاسم الأول (٣ = الاسم الثلاثي).',
   false, 72, 2, 5),
  ('daughter_sons_father_min_words', '3'::jsonb, '3'::jsonb, 'int', 'tree',
   'أقل عدد كلمات في «اسم الأب الكامل»',
   'الأب من خارج العائلة يُكتب سطراً واحداً؛ أقل عدد كلمات مقبول (٣ = ثلاثي). «اسم الجد إلزامي» القديم مفعّلاً = ٤ على الأقل.',
   false, 73, 2, 6)
on conflict (key) do nothing;

update public.app_config
   set label_ar = replace(label_ar, '«نسبك»', '«أكمل حسابك»'),
       help_ar  = replace(replace(replace(help_ar, 'يكمل نسبه', 'يكمل حسابه'),
                                  'قبل إرسال نسبه', 'قبل إرسال «أكمل حسابك»'),
                          '«أبوي مو موجود» يطلب اسم الجد أيضاً. اسم الأب الأول واسم أبيه واسم العائلة إلزامية دائماً.',
                          '«اسم الأب الكامل» أربع كلمات على الأقل (وإلا «أقل عدد كلمات في اسم الأب الكامل»).')
 where key in ('daughter_sons_enabled', 'daughter_sons_allow_later', 'daughter_sons_require_grandfather');

update public.app_config
   set help_ar = 'نصوص تحل محل نصوص التطبيق (الفارغ = نص التطبيق): option_title، option_subtitle، intro_title، intro_subtitle، intro_body، page_title، page_subtitle، mother_title، mother_placeholder، mother_hint، new_mother_title، new_mother_name_title، new_mother_father_title، father_title، father_name_title، send_button، pending_title، pending_note، sent_body، rejected_title، home_title، home_body، home_pending_title، home_pending_body، home_rejected_title، home_rejected_body، locked_title، locked_body، locked_pending_title، locked_pending_body، locked_button، outside_tag، son_tag، inbox_title، outside_husband_title؛ وإشعارات السيرفر: notify_join_body، notify_rejected_title، notify_rejected_body، notify_completed_title.'
 where key = 'daughter_sons_texts';

-- ── ١) نص من daughter_sons_texts وإلا الافتراضي (للدوال فقط) ──
create or replace function private.daughter_sons_text(p_key text, p_default text)
 returns text
 language sql
 stable
 security definer
 set search_path to ''
as $function$
  select coalesce(nullif(btrim((select c.value ->> p_key from public.app_config c
                                 where c.key = 'daughter_sons_texts' and jsonb_typeof(c.value) = 'object')), ''),
                  p_default);
$function$;
revoke all on function private.daughter_sons_text(text, text) from public, anon, authenticated;

do $mig$
declare d text := pg_get_functiondef('public.approve_join_as_daughter_son(uuid)'::regprocedure); n text;
begin
  n := replace(d, $x$'تم قبول طلب انضمامك — افتح التطبيق واختر أمّك واكتب اسم أبوك ليكتمل نسبك'$x$,
                  $x$private.daughter_sons_text('notify_join_body', 'تم قبول طلب انضمامك — افتح التطبيق واضغط «أكمل حسابك»: اختر أمّك واكتب اسم أبوك')$x$);
  if n = d then raise exception 'approve_join_as_daughter_son: نص الحي تغيّر — راجع الترحيل'; end if;
  execute n;
end $mig$;

-- ── ٢) القفل على السيرفر ──
-- true = المتصل ابن بنت لم يكتمل حسابه (يحتاج أو قيد المراجعة) والقسم في القائمة. بحث واحد بالمفتاح الأساسي؛
-- غير المُعلَّم (كل الأعضاء الآخرين) = false. يُستدعى في السياسات داخل (select …) فيُحسب مرة لكل استعلام.
create or replace function public.lineage_locked(p_section text)
 returns boolean
 language sql
 stable
 security definer
 set search_path to ''
as $function$
  select exists (select 1 from public.daughter_son_lineage d
                  where d.profile_id = public.current_profile_id() and d.completed_at is null)
     and coalesce(public.current_user_role(), '') not in ('owner', 'admin', 'monitor', 'supervisor')
     and coalesce((select case when jsonb_typeof(c.value) = 'array' then c.value ? p_section end
                     from public.app_config c where c.key = 'daughter_sons_locked_sections'),
                  p_section = any (array['diwaniyas', 'projects', 'library', 'women_tree', 'member_details']));
$function$;
comment on function public.lineage_locked(text) is
  'Caller is a daughter''s son whose «أكمل حسابك» is not approved yet and the section is in app_config.daughter_sons_locked_sections. Used by RESTRICTIVE select policies.';
revoke all on function public.lineage_locked(text) from public, anon;
grant execute on function public.lineage_locked(text) to authenticated;

drop policy if exists diwaniyas_lineage_locked on public.diwaniyas;
create policy diwaniyas_lineage_locked on public.diwaniyas as restrictive for select to authenticated
  using (not (select public.lineage_locked('diwaniyas')));
drop policy if exists projects_lineage_locked on public.projects;
create policy projects_lineage_locked on public.projects as restrictive for select to authenticated
  using (not (select public.lineage_locked('projects')));
drop policy if exists family_archive_lineage_locked on public.family_archive;
create policy family_archive_lineage_locked on public.family_archive as restrictive for select to authenticated
  using (not (select public.lineage_locked('library')));
drop policy if exists women_members_lineage_locked on public.women_members;
create policy women_members_lineage_locked on public.women_members as restrictive for select to authenticated
  using (not (select public.lineage_locked('women_tree')));

-- ── ٣) البحث بلا تصفّح ──
-- كلمات الاسم كما في التطبيقات (NameSearch.words): بلا تشكيل ولا تطويل، أ إ آ ٱ ← ا، ة ← ه، ى ← ي، و«عبد» ملصقة بما بعدها
create or replace function private.lineage_name_words(p_text text)
 returns text[]
 language plpgsql
 immutable
 set search_path to ''
as $function$
declare
  parts text[];
  out   text[] := '{}';
  i     int := 1;
  n     int;
begin
  parts := regexp_split_to_array(
             translate(lower(regexp_replace(coalesce(p_text, ''), '[ً-ٰٟـ]', '', 'g')),
                       'أإآٱةى', 'ااااهي'),
             '[^ء-ي٠-٩ٱ-ۿa-z0-9]+');
  parts := array_remove(parts, '');
  n := coalesce(array_length(parts, 1), 0);
  while i <= n loop
    if parts[i] = 'عبد' and i < n then
      out := out || (parts[i] || parts[i + 1]);
      i := i + 2;
    else
      out := out || parts[i];
      i := i + 1;
    end if;
  end loop;
  return out;
end;
$function$;
revoke all on function private.lineage_name_words(text) from public, anon, authenticated;

-- مطابقة سلسلة من الاسم الأول (NameSearch.chainMatch fromStart): ٠ = الكلمة الأخيرة كاملة، ١ = ناقصة، null = لا تطابق
create or replace function private.lineage_chain_rank(p_words text[], p_joined text)
 returns int
 language plpgsql
 immutable
 set search_path to ''
as $function$
declare
  acc text := '';
  w   text;
begin
  if p_joined is null or p_joined = '' then return null; end if;
  foreach w in array coalesce(p_words, '{}') loop
    acc := acc || w;
    if acc = p_joined then return 0; end if;
    if length(acc) >= length(p_joined) then
      return case when left(acc, length(p_joined)) = p_joined then 1 end;
    end if;
  end loop;
  return null;
end;
$function$;
revoke all on function private.lineage_chain_rank(text[], text) from public, anon, authenticated;

-- المتصل: ابن بنت لم يكتمل حسابه — وإلا 42501
create or replace function private.lineage_require_open()
 returns uuid
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
declare me uuid := public.current_profile_id();
begin
  if me is null or not public.is_approved_member()
     or not exists (select 1 from public.daughter_son_lineage d where d.profile_id = me and d.completed_at is null) then
    raise exception 'للحساب الذي يكمل بياناته فقط' using errcode = '42501', hint = 'not_allowed';
  end if;
  return me;
end;
$function$;
revoke all on function private.lineage_require_open() from public, anon, authenticated;

create or replace function public.search_daughters_for_lineage(p_query text)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
declare
  q    text[] := private.lineage_name_words(left(coalesce(p_query, ''), 200));
  minp int := least(5, greatest(2, public.config_int('daughter_sons_mother_min_parts', 3)));
  j    text;
begin
  perform private.lineage_require_open();
  if coalesce(array_length(q, 1), 0) < minp then
    return '[]'::jsonb;
  end if;
  j := array_to_string(q, '');
  return coalesce((
    select jsonb_agg(x.o order by x.rank, x.sort_order, x.full_name)
      from (
        select jsonb_build_object(
                 'id', w.id,
                 'first_name', coalesce(w.first_name, ''),
                 'full_name', coalesce(nullif(btrim(w.full_name), ''), w.first_name, ''),
                 'father_name', coalesce(nullif(btrim(f.full_name), ''), f.first_name),
                 'husband_id', w.husband_id,
                 'husband_name', coalesce(nullif(btrim(h.full_name), ''), h.first_name),
                 'husband_in_family', h.id is not null and (
                     exists (select 1 from public.profiles x where x.id = h.id)
                     or (h.parent_id is not null and not coalesce(h.is_outside_family, false)))) as o,
               r.rank, w.sort_order, w.full_name
          from public.women_members w
          join public.women_members f on f.id = w.parent_id and lower(coalesce(f.gender, 'male')) = 'male'
          left join public.women_members h on h.id = w.husband_id
          cross join lateral (select private.lineage_chain_rank(
                                private.lineage_name_words(coalesce(nullif(btrim(w.full_name), ''), w.first_name)), j) as rank) r
         where lower(coalesce(w.gender, '')) = 'female'
           and not coalesce(w.is_hidden_from_tree, false)
           and not coalesce(w.is_web_only, false)
           and r.rank is not null
         order by r.rank, w.sort_order, w.full_name
         limit 10) x), '[]'::jsonb);
end;
$function$;

-- «ما لقيت أمي؟»: أبوها من شجرة الرجال — نفس قاعدة الخصوصية
create or replace function public.search_men_for_lineage(p_query text)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
declare
  me   uuid := private.lineage_require_open();
  q    text[] := private.lineage_name_words(left(coalesce(p_query, ''), 200));
  minp int := least(5, greatest(2, public.config_int('daughter_sons_mother_min_parts', 3)));
  j    text;
begin
  if coalesce(array_length(q, 1), 0) < minp then
    return '[]'::jsonb;
  end if;
  j := array_to_string(q, '');
  return coalesce((
    select jsonb_agg(x.o order by x.rank, x.sort_order, x.full_name)
      from (
        select jsonb_build_object(
                 'id', p.id,
                 'full_name', coalesce(nullif(btrim(p.full_name), ''), p.first_name, ''),
                 'is_deceased', coalesce(p.is_deceased, false)) as o,
               r.rank, p.sort_order, p.full_name
          from public.profiles p
          cross join lateral (select private.lineage_chain_rank(
                                private.lineage_name_words(coalesce(nullif(btrim(p.full_name), ''), p.first_name)), j) as rank) r
         where lower(coalesce(p.gender, 'male')) <> 'female'
           and not coalesce(p.is_hidden_from_tree, false)
           and coalesce(p.role, '') <> 'pending'
           and p.id <> me
           and r.rank is not null
         order by r.rank, p.sort_order, p.full_name
         limit 10) x), '[]'::jsonb);
end;
$function$;

-- ── ٤) الإرسال: «اسم الأب الكامل» سطراً واحداً + «ما لقيت أمي؟» ──
drop function if exists public.submit_daughter_son_lineage(uuid, uuid, text, text, text, text, boolean);
create function public.submit_daughter_son_lineage(
  p_mother_id uuid default null,
  p_father_id uuid default null,
  p_first_name text default null,
  p_father_name text default null,
  p_grandfather_name text default null,
  p_family_name text default null,
  p_father_deceased boolean default false,
  p_father_full_name text default null,
  p_new_mother_name text default null,
  p_new_mother_father_id uuid default null,
  p_new_mother_deceased boolean default false)
 returns uuid
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  me      uuid := public.current_profile_id();
  l       public.daughter_son_lineage%rowtype;
  mom     public.women_members%rowtype;
  dad     public.women_members%rowtype;
  gf      public.profiles%rowtype;
  f1      text := btrim(coalesce(p_first_name, ''));
  f2      text := btrim(coalesce(p_father_name, ''));
  f3      text := btrim(coalesce(p_grandfather_name, ''));
  f4      text := btrim(coalesce(p_family_name, ''));
  fl      text := btrim(regexp_replace(coalesce(p_father_full_name, ''), '\s+', ' ', 'g'));
  nm      text := btrim(regexp_replace(coalesce(p_new_mother_name, ''), '\s+', ' ', 'g'));
  is_new  boolean := p_mother_id is null;
  legacy  boolean;
  minw    int;
  fname   text;
  fdead   boolean;
  mname   text;
  me_name text;
  payload jsonb;
  rid     uuid;
begin
  if me is null or not public.is_approved_member() then
    raise exception 'للأعضاء المفعّلين' using errcode = '42501', hint = 'not_allowed';
  end if;
  select * into l from public.daughter_son_lineage where profile_id = me for update;
  if not found or l.completed_at is not null then
    raise exception 'حسابك مكتمل' using errcode = 'P0001', hint = 'not_needed';
  end if;
  if exists (select 1 from public.admin_requests r
              where r.request_type = 'lineage_request' and r.requester_id = me and r.status = 'pending') then
    raise exception 'طلبك عند الإدارة' using errcode = 'P0001', hint = 'already_pending';
  end if;
  if public.config_int('daughter_sons_max_resubmits', 3) > 0
     and (select count(*) from public.admin_requests r
           where r.request_type = 'lineage_request' and r.requester_id = me and r.status = 'rejected'
             and r.created_at >= l.approved_at) > public.config_int('daughter_sons_max_resubmits', 3) then
    raise exception 'وصلت حد المحاولات — تواصل مع الإدارة' using errcode = 'P0001', hint = 'resubmit_limit';
  end if;

  if not is_new then
    -- الأم: بنت من بنات العائلة في شجرة النساء (أنثى لها أب ذكر)
    select * into mom from public.women_members where id = p_mother_id;
    if not found or lower(coalesce(mom.gender, '')) <> 'female' or mom.parent_id is null
       or not exists (select 1 from public.women_members f
                       where f.id = mom.parent_id and lower(coalesce(f.gender, 'male')) = 'male') then
      raise exception 'اختر أمّك من بنات العائلة' using errcode = 'P0001', hint = 'bad_mother';
    end if;
    mname := coalesce(nullif(btrim(mom.full_name), ''), mom.first_name);
  else
    -- «ما لقيت أمي؟»: اسمها + أبوها من شجرة الرجال (التكرار بالاسم مسموح — الإدارة تقرّر)
    if nm = '' or p_new_mother_father_id is null then
      raise exception 'اكتب اسم أمّك واختر أبوها' using errcode = '22023', hint = 'name_required';
    end if;
    if length(nm) > 120 then
      raise exception 'الاسم طويل' using errcode = '22023', hint = 'name_too_long';
    end if;
    select * into gf from public.profiles
     where id = p_new_mother_father_id and lower(coalesce(gender, 'male')) <> 'female'
       and not coalesce(is_hidden_from_tree, false) and coalesce(role, '') <> 'pending' and id <> me;
    if not found then
      raise exception 'أبوها غير موجود في شجرة العائلة' using errcode = 'P0001', hint = 'mother_father_not_found';
    end if;
    if p_father_id is not null then
      raise exception 'الأم الجديدة بلا زوج مسجّل — اكتب اسم أبوك' using errcode = 'P0001', hint = 'bad_father';
    end if;
    mname := nm;
  end if;

  if p_father_id is not null then
    if mom.husband_id is distinct from p_father_id then
      raise exception 'هذا ليس زوج أمّك المسجّل' using errcode = 'P0001', hint = 'bad_father';
    end if;
    select * into dad from public.women_members where id = p_father_id;
    -- زوجها من العائلة (له ملف في الشجرة) → مكان ابنه شجرة الرجال
    if exists (select 1 from public.profiles x where x.id = p_father_id) or dad.parent_id is not null then
      raise exception 'أبوك من العائلة — اطلب «ربط بالشجرة» من الإدارة' using errcode = 'P0001', hint = 'father_in_family';
    end if;
    fname := coalesce(nullif(btrim(dad.full_name), ''), dad.first_name);
    fdead := coalesce(dad.is_deceased, false);
  else
    if not is_new and mom.husband_id is not null then
      raise exception 'لأمّك زوج مسجّل — اختره' using errcode = 'P0001', hint = 'mother_has_husband';
    end if;
    -- «اسم الأب الكامل» سطراً واحداً؛ النسخ القديمة ترسل الحقول الأربعة
    legacy := fl = '';
    if legacy then
      fl := btrim(regexp_replace(concat_ws(' ', nullif(f1, ''), nullif(f2, ''), nullif(f3, ''), nullif(f4, '')), '\s+', ' ', 'g'));
    end if;
    minw := least(6, greatest(2, public.config_int('daughter_sons_father_min_words', 3)));
    if public.config_bool('daughter_sons_require_grandfather', false) then
      minw := greatest(minw, 4);
    end if;
    if fl = '' or coalesce(array_length(string_to_array(fl, ' '), 1), 0) < minw
       or (legacy and (f1 = '' or f2 = '' or f4 = '')) then
      raise exception 'اكتب اسم الأب الكامل' using errcode = '22023', hint = 'name_required';
    end if;
    if length(fl) > 120 or greatest(length(f1), length(f2), length(f3), length(f4)) > 40 then
      raise exception 'الاسم طويل' using errcode = '22023', hint = 'name_too_long';
    end if;
    fname := fl;
    fdead := coalesce(p_father_deceased, false);
  end if;

  select coalesce(nullif(btrim(p.full_name), ''), p.first_name) into me_name from public.profiles p where p.id = me;
  payload := jsonb_build_object(
    'v', 2,
    'mother_id', case when is_new then null else mom.id end,
    'mother_name', mname,
    'new_mother', case when is_new then jsonb_build_object(
                    'name', nm, 'first_name', split_part(nm, ' ', 1),
                    'father_id', gf.id, 'father_name', coalesce(nullif(btrim(gf.full_name), ''), gf.first_name),
                    'is_deceased', coalesce(p_new_mother_deceased, false)) end,
    'father_id', p_father_id,
    'father_name', fname,
    'father_is_deceased', fdead,
    'father', case when p_father_id is null then jsonb_build_object(
                'first_name', split_part(fname, ' ', 1), 'full_name', fname, 'is_deceased', fdead)
                || case when legacy then jsonb_build_object('father_name', f2, 'grandfather_name', nullif(f3, ''),
                                                            'family_name', f4) else '{}'::jsonb end end,
    'summary', 'نسب ' || coalesce(me_name, '') || ': أمّه ' || mname
               || case when is_new then ' (أم جديدة)' else '' end || ' · أبوه ' || fname);

  perform set_config('app.lineage_rpc', 'on', true);
  insert into public.admin_requests (member_id, requester_id, request_type, status, details, new_value)
  values (me, me, 'lineage_request', 'pending', payload::text, case when is_new then null else mom.id::text end)
  returning id into rid;
  perform set_config('app.lineage_rpc', '', true);

  insert into public.notifications (target_member_id, title, body, kind, created_by)
  select s.id, 'طلب نسب جديد', coalesce(me_name, 'عضو') || ' اختار أمّه وأبوه — بانتظار التأكيد', 'admin', me
    from public.profiles s
   where s.role in ('owner', 'admin', 'monitor') and s.status = 'active' and s.id <> me;

  return rid;
end;
$function$;

-- ── ٥) قرار الإدارة: «أم جديدة» + نصوص «أكمل حسابك» ──
create or replace function public.decide_lineage_request(p_request_id uuid, p_decision text, p_reason text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  uid      uuid := auth.uid();
  me       uuid := public.current_profile_id();
  my_role  text := coalesce(public.current_user_role(), 'pending');
  decision text := lower(btrim(coalesce(p_decision, '')));
  reason   text := nullif(btrim(coalesce(p_reason, '')), '');
  r        public.admin_requests%rowtype;
  d        jsonb;
  nmj      jsonb;
  l        public.daughter_son_lineage%rowtype;
  son      public.profiles%rowtype;
  gf       public.profiles%rowtype;
  gnode    public.women_members%rowtype;
  mom      public.women_members%rowtype;
  gfid     uuid;
  mfirst   text;
  hid      uuid;
  hname    text;
  son_id   uuid;
  son_first text;
  new_mom  boolean := false;
begin
  if my_role not in ('owner', 'admin', 'monitor') then
    raise exception 'طلبات النسب للمالك والمدير والمراقب' using errcode = '42501', hint = 'not_allowed';
  end if;
  if decision not in ('approve', 'reject') then
    raise exception 'bad_decision' using errcode = '22023', hint = 'bad_decision';
  end if;
  select * into r from public.admin_requests where id = p_request_id for update;
  if not found or r.request_type is distinct from 'lineage_request' then
    raise exception 'الطلب غير موجود' using errcode = 'P0001', hint = 'request_not_found';
  end if;
  if r.status is distinct from 'pending' then
    raise exception 'الطلب عولج من قبل' using errcode = 'P0001', hint = 'already_handled';
  end if;
  if my_role <> 'owner' and (r.requester_id = any (array[uid, me]) or r.member_id = any (array[uid, me])) then
    raise exception 'لا تقرّر في طلبك' using errcode = '42501', hint = 'own_request';
  end if;

  if decision = 'reject' then
    update public.admin_requests
       set status = 'rejected', admin_reply = reason, replied_by = me, replied_at = now()
     where id = r.id;
    insert into public.notifications (target_member_id, title, body, kind, created_by)
    values (r.requester_id,
            private.daughter_sons_text('notify_rejected_title', 'راجع بياناتك وأرسلها من جديد'),
            private.daughter_sons_text('notify_rejected_body', 'افتح «أكمل حسابك» وراجع اختيار أمّك وأبوك')
              || coalesce(E'\nالسبب: ' || reason, ''), 'request_rejected', me);
    return jsonb_build_object('ok', true, 'request_id', r.id, 'status', 'rejected');
  end if;

  begin
    d := r.details::jsonb;
  exception when others then
    d := null;
  end;
  if d is null or jsonb_typeof(d) <> 'object' then
    raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload';
  end if;
  nmj := d->'new_mother';
  new_mom := nmj is not null and jsonb_typeof(nmj) = 'object';
  if not new_mom and coalesce(d->>'mother_id', '') = '' then
    raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload';
  end if;

  select * into l from public.daughter_son_lineage where profile_id = r.requester_id for update;
  if not found or l.completed_at is not null then
    raise exception 'نسب العضو مكتمل' using errcode = 'P0001', hint = 'not_needed';
  end if;
  select * into son from public.profiles where id = r.requester_id;
  if not found then
    raise exception 'صاحب الطلب لم يعد له حساب' using errcode = 'P0001', hint = 'requester_gone';
  end if;
  if exists (select 1 from public.women_members w where w.linked_user_id = son.id) then
    raise exception 'الحساب مربوط بشجرة النساء من قبل' using errcode = 'P0001', hint = 'already_linked';
  end if;

  if new_mom then
    -- «أم جديدة»: بنت لعقدة أبيها في شجرة النساء (نسخة رجل الشجرة بنفس المعرّف — تُنشأ إن غابت)
    begin
      gfid := (nmj->>'father_id')::uuid;
    exception when others then
      gfid := null;
    end;
    mfirst := btrim(coalesce(nmj->>'first_name', ''));
    select * into gf from public.profiles where id = gfid and lower(coalesce(gender, 'male')) <> 'female';
    if not found or mfirst = '' or coalesce(d->>'father_id', '') <> '' then
      raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload';
    end if;
    select * into gnode from public.women_members where id = gf.id for update;
    if not found then
      insert into public.women_members (id, first_name, full_name, parent_id, gender, is_deceased, sort_order)
      values (gf.id, gf.first_name, coalesce(nullif(btrim(gf.full_name), ''), gf.first_name),
              (select w.id from public.women_members w where w.id = gf.father_id), 'male',
              coalesce(gf.is_deceased, false), coalesce(gf.sort_order, 0))
      returning * into gnode;
    elsif lower(coalesce(gnode.gender, 'male')) <> 'male' then
      raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload';
    end if;
    insert into public.women_members (id, first_name, full_name, parent_id, gender, is_deceased, is_married, sort_order)
    values (gen_random_uuid(), mfirst,
            btrim(mfirst || ' ' || coalesce(nullif(btrim(gnode.full_name), ''), btrim(coalesce(gnode.first_name, '')))),
            gnode.id, 'female', coalesce((nmj->>'is_deceased')::boolean, false), true,
            coalesce((select max(c.sort_order) + 1 from public.women_members c where c.parent_id = gnode.id), 0))
    returning * into mom;
  else
    select * into mom from public.women_members where id = (d->>'mother_id')::uuid for update;
    if not found or lower(coalesce(mom.gender, '')) <> 'female' or mom.parent_id is null then
      raise exception 'الأم لم تعد في شجرة النساء' using errcode = 'P0001', hint = 'bad_mother';
    end if;
  end if;

  if coalesce(d->>'father_id', '') <> '' then
    hid := (d->>'father_id')::uuid;
    if mom.husband_id is distinct from hid then
      raise exception 'زوج الأم تغيّر بعد الطلب' using errcode = 'P0001', hint = 'mother_changed';
    end if;
    if exists (select 1 from public.profiles x where x.id = hid) then
      raise exception 'الأب من العائلة — «ربط بالشجرة»' using errcode = 'P0001', hint = 'father_in_family';
    end if;
    select coalesce(nullif(btrim(full_name), ''), first_name) into hname from public.women_members where id = hid;
  else
    if mom.husband_id is not null then
      raise exception 'للأم زوج مسجّل الآن — يرسل العضو طلبه من جديد' using errcode = 'P0001', hint = 'mother_has_husband';
    end if;
    hname := btrim(coalesce(d->>'father_name', ''));
    if hname = '' or coalesce(btrim(d->'father'->>'first_name'), '') = '' then
      raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload';
    end if;
    insert into public.women_members (id, first_name, full_name, gender, parent_id, is_married, is_deceased,
                                      is_outside_family, sort_order)
    values (gen_random_uuid(), btrim(d->'father'->>'first_name'), hname, 'male', null, true,
            coalesce((d->'father'->>'is_deceased')::boolean, false), true, 0)
    returning id into hid;
    update public.women_members set husband_id = hid, is_married = true where id = mom.id;
  end if;

  son_first := coalesce(nullif(btrim(son.first_name), ''), split_part(btrim(coalesce(son.full_name, '')), ' ', 1));
  insert into public.women_members (id, first_name, full_name, gender, parent_id, mother_id, linked_user_id,
                                    is_deceased, sort_order)
  values (gen_random_uuid(), son_first, btrim(son_first || ' ' || hname), 'male', hid, mom.id, son.id, false,
          coalesce((select max(c.sort_order) + 1 from public.women_members c where c.parent_id = hid), 0))
  returning id into son_id;

  update public.daughter_son_lineage set completed_at = now(), women_node_id = son_id where profile_id = son.id;
  update public.admin_requests set status = 'approved', replied_by = me, replied_at = now() where id = r.id;

  insert into public.notifications (target_member_id, title, body, kind, created_by)
  values (son.id, private.daughter_sons_text('notify_completed_title', 'اكتمل حسابك'),
          'صرت في شجرة النساء تحت أمّك ' || coalesce(nullif(btrim(mom.first_name), ''), '')
          || ' وأبوك ' || hname, 'admin', me);

  return jsonb_build_object('ok', true, 'request_id', r.id, 'status', 'approved',
                            'mother_id', mom.id, 'new_mother', new_mom,
                            'husband_id', hid, 'son_node_id', son_id);
end;
$function$;

-- ── الصلاحيات ──
revoke all on function public.search_daughters_for_lineage(text) from public, anon;
revoke all on function public.search_men_for_lineage(text) from public, anon;
revoke all on function public.submit_daughter_son_lineage(uuid, uuid, text, text, text, text, boolean, text, text, uuid, boolean) from public, anon;
grant execute on function public.search_daughters_for_lineage(text) to authenticated;
grant execute on function public.search_men_for_lineage(text) to authenticated;
grant execute on function public.submit_daughter_son_lineage(uuid, uuid, text, text, text, text, boolean, text, text, uuid, boolean) to authenticated;
