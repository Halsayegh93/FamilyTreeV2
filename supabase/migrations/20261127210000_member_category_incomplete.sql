-- مطبَّق على الحي ٢٠٢٦-١١-٢٧ بعد تجربة begin…rollback (حساب المراجعة يبقى daughter_son، حسين daughter_son، عضو العائلة family_man)
-- NOT APPLIED — يطبّقه المدير بعد تجربة begin…rollback وموافقة المالك. فوق 20261127190000_member_category_access (حيّ).
-- فئة سابعة في «صلاحيات الأعضاء حسب الفئة» (المالك ٢٠٢٦-١١-٢٧ «ضيفهم في صلاحيات الأعضاء حسب الفئة»):
--   `incomplete` «لم يستكمل التسجيل» — أبناء وبنات البنات قبل استكمال التسجيل: صفّ في daughter_son_lineage بلا completed_at
--   ولا limited_at (ومنه من أرسل اسم الوالدة وينتظر الإدارة). الترتيب في my_member_category(): limited ثم incomplete ثم
--   daughter_son/daughter_daughter … . حساب المراجعة (review_account_ids()) مستثنى ويبقى في فئته اليوم.
--   الافتراضي (صفّ غائب في الجدول) = كل شيء ظاهر = ما يحصل عليه ابن/بنت البنت اليوم، وقفل «استكمال التسجيل»
--   (daughter_sons_locked_sections في lineage_locked) كما هو حرفياً — لا يتغيّر شيء على أحد حتى يعدّل المالك.
--   الفحص (private.member_category_access_problem) يقرأ الفئات من private.member_access_categories() فتُقبل الفئة الجديدة.
-- التراجع: rollback/20261127210000_member_category_incomplete_rollback.sql
-- التجربة: cd supabase/tests/family_links && node member_category_access.test.mjs

create or replace function private.member_access_categories()
returns text[]
language sql
immutable
set search_path to ''
as $function$
  select array['family_man', 'family_woman', 'daughter_son', 'daughter_daughter', 'limited', 'incomplete', 'outside_spouse'];
$function$;

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
  -- «لم يستكمل التسجيل» (20261127210000): صفّ نسب بلا completed_at ولا limited_at — ومنه من أرسل اسم الوالدة وينتظر
  -- الإدارة. حساب المراجعة (review_account_ids) يبقى في فئته اليوم
  if exists (select 1 from public.daughter_son_lineage d
              where d.profile_id = v_me and d.completed_at is null and d.limited_at is null)
     and not (v_me = any (public.review_account_ids())) then
    return 'incomplete';
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
  'Caller''s member category for app_config.member_category_access: staff · family_man · family_woman · daughter_son · daughter_daughter · limited · incomplete · outside_spouse; null when not an active member.';

revoke all on function private.member_access_categories() from public, anon, authenticated;
revoke all on function public.my_member_category() from public, anon;
grant execute on function public.my_member_category() to authenticated;
