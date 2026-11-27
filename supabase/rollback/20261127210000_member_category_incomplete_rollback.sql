-- التراجع عن 20261127210000_member_category_incomplete: صفّ «incomplete» يُحذف من الجدول أولاً (والفئات الجديدة ما زالت
-- مقبولة)، ثم private.member_access_categories() وpublic.my_member_category() كما في 20261127190000 حرفياً.
update public.app_config
   set value = value - 'incomplete'
 where key = 'member_category_access' and jsonb_typeof(value) = 'object' and value ? 'incomplete';
update public.app_config
   set default_value = default_value - 'incomplete'
 where key = 'member_category_access' and jsonb_typeof(default_value) = 'object' and default_value ? 'incomplete';

create or replace function private.member_access_categories()
returns text[]
language sql
immutable
set search_path to ''
as $function$
  select array['family_man', 'family_woman', 'daughter_son', 'daughter_daughter', 'limited', 'outside_spouse'];
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
