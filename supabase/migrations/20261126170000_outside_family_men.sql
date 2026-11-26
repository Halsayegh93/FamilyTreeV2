-- «أزواج البنات» — طلب المالك ٢٠٢٦-١١-٢٦: «اي اسم رجل خارج العائلة حطه في ازواج البنات».
--
-- `women_members.is_outside_family` على الذكر = زوج بنت من خارج العائلة (يُرسم تحت زوجته، ويُعدّ في
-- «أزواج البنات» في الآيفون والأندرويد والموقع). كان يُعلَّم فقط حين يُضاف عبر `add_outside_husband`،
-- فبقي رجل من خارج العائلة أُضيف بطريق آخر بلا علامة («عبدالعزيز القلاف»، ٢٠٢٦-٠٨-٠٩) — لا في أزواج البنات
-- ولا في غيرها.
--
-- القاعدة للذكر في شجرة النساء:
--   • نسخة رجل من العائلة (نفس المعرّف في `profiles`) → لا تُمسّ
--   • أبوه رجل من العائلة → false (من العائلة)
--   • له أب آخر أو أمّ في الشجرة → لا تُمسّ (ابن بنت: «أبناء البنات»)
--   • اسمه «المحمدعلي» → لا تُمسّ (من العائلة على الأغلب، يُربط بأبيه)
--   • غير ذلك (رجل بلا أب ولا أمّ في الشجرة، ليس من رجال العائلة) → true: «أزواج البنات»
-- التعديل بلا مستخدم فلا إشعارات (`notify_member_change`). الإناث كما هنّ (`trg_women_outside_flag`).
-- التراجع: supabase/rollback/20261126170000_outside_family_men_rollback.sql

create or replace function private.women_outside_male(p_id uuid, p_parent uuid, p_mother uuid, p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    -- نسخة رجل من العائلة في شجرة النساء
    when p_id is not null and exists (select 1 from public.profiles p where p.id = p_id) then null
    -- ابن رجل من العائلة
    when p_parent is not null and exists (select 1 from public.profiles p where p.id = p_parent) then false
    -- ابن بنت (أبوه زوج من خارج العائلة، أو أمّه بنت بلا أب مسجّل)
    when p_parent is not null or p_mother is not null then null
    -- «المحمدعلي» بلا أب: يُربط بأبيه، لا يُعلَّم
    when replace(coalesce(p_name, ''), ' ', '') like '%المحمدعلي%' then null
    -- رجل من خارج العائلة: زوج بنت
    else true
  end
$$;

revoke all on function private.women_outside_male(uuid, uuid, uuid, text) from public;

create or replace function private.women_outside_male_flag()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v boolean;
begin
  if lower(coalesce(new.gender, '')) <> 'male' then
    return new;
  end if;
  v := private.women_outside_male(new.id, new.parent_id, new.mother_id,
                                  coalesce(nullif(new.full_name, ''), new.first_name));
  if v is not null then
    new.is_outside_family := v;
  end if;
  return new;
end;
$$;

revoke all on function private.women_outside_male_flag() from public;

drop trigger if exists trg_women_outside_male_flag on public.women_members;
create trigger trg_women_outside_male_flag
  before insert or update of parent_id, mother_id, full_name, first_name, gender
  on public.women_members
  for each row execute function private.women_outside_male_flag();

-- من عُلِّم الحين (للمراجعة والتراجع)
create table if not exists private.outside_men_backfill (
  id uuid primary key,
  flagged_at timestamptz not null default now()
);

insert into private.outside_men_backfill (id)
select w.id
from public.women_members w
where lower(coalesce(w.gender, '')) = 'male'
  and not w.is_outside_family
  and private.women_outside_male(w.id, w.parent_id, w.mother_id,
                                 coalesce(nullif(w.full_name, ''), w.first_name)) is true
on conflict (id) do nothing;

update public.women_members w
set is_outside_family = true
from private.outside_men_backfill b
where b.id = w.id
  and not w.is_outside_family;
