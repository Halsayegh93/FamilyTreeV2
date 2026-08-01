-- مُستخرَجة من سجل الإنتاج (supabase_migrations.schema_migrations)
-- كانت مطبَّقة على القاعدة لكن ملفها مفقود من المستودع.

-- اسم العائلة يورَّث: تغييره عند العضو يسري على أبنائه وأحفاده،
-- لأن العائلة صفة نسب لا اختيار فردي منفصل لكل ابن.
create or replace function public.set_family_name_cascade(
  p_member_id uuid,
  p_family    text
)
returns int
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  affected int;
begin
  -- الصلاحية: العضو نفسه، أو المالك/المدير
  if not (
    p_member_id = auth.uid()
    or current_user_role() = any (array['owner','admin'])
  ) then
    raise exception 'not_allowed';
  end if;

  with recursive line as (
    select id from public.profiles where id = p_member_id
    union all
    select p.id from public.profiles p join line l on p.father_id = l.id
  )
  update public.profiles
     set family_name = nullif(trim(p_family), '')
   where id in (select id from line);

  get diagnostics affected = row_count;
  return affected;
end;
$$;

-- ابن جديد يرث عائلة أبيه تلقائياً عند الإضافة
create or replace function public.inherit_family_name()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if new.family_name is null and new.father_id is not null then
    select family_name into new.family_name
      from public.profiles where id = new.father_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_inherit_family_name on public.profiles;
create trigger trg_inherit_family_name
  before insert on public.profiles
  for each row execute function public.inherit_family_name();;
