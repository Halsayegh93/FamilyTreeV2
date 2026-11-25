-- «النساء من خارج العائلة» — طلب المالك ٢٠٢٦-١١-٢٦: «الإناث اللي من خارج العائلة ما انضافوا بالقسم خارج العائلة»
-- (العينة ١ المعروضة ٢٠٢٦-١١-٢٥: «يُميَّزن بعلامة ويُحسبن وحدهن، سواء لهن حساب أو لا»).
--
-- `women_members.is_outside_family` كان للأزواج من خارج العائلة فقط. الحين تُعلَّم به الأنثى أيضاً حين تكون:
--   ١) زوجة بلا أب في الشجرة واسمها ليس «المحمدعلي» (من عائلة ثانية)
--   ٢) بنت زوج من خارج العائلة (أبوها عقدة معلَّمة)
--   ٣) بنت بنت بلا أب مسجّل وغير متزوجة (أمّها بنت رجل من العائلة، وزوج الأم ليس من العائلة)
-- وتُلغى العلامة حين يصير أبوها رجلاً من العائلة. «المحمدعلي» بلا أب لا تُعلَّم (تُربط بأبيها).
--
-- لماذا العمود نفسه: أرقام «العائلة» في الآيفون والأندرويد تعدّ إناث `is_outside_family` في «خارج العائلة»
-- وتطرحهن من «النساء» من قبل — فيصحّ العدد بلا تحديث. كل الدوال (`add_outside_husband`،
-- `women_family_*`، `search_daughters_for_lineage`، `decide_lineage_request`) والتطبيقات تقرأ العمود عن
-- الزوج أو الأب (ذكر) فقط، فلا يتغيّر سلوكها. التعديل بلا مستخدم فلا إشعارات (`notify_member_change`).
-- التراجع: supabase/rollback/20261126090000_outside_family_women_rollback.sql

-- القاعدة الواحدة: true = من خارج العائلة، false = من العائلة، null = اتركها كما هي
create or replace function private.women_outside_female(p_parent uuid, p_husband uuid, p_mother uuid, p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    -- بنت رجل من العائلة
    when p_parent is not null and exists (select 1 from public.profiles p where p.id = p_parent) then false
    -- بنت زوج من خارج العائلة
    when p_parent is not null and exists (select 1 from public.women_members h
                                           where h.id = p_parent and h.is_outside_family) then true
    when p_parent is not null then null
    -- بنت بنت بلا أب مسجّل وغير متزوجة: أمّها بنت رجل من العائلة وزوج الأم ليس من العائلة
    -- (قبل فحص الاسم — اسمها يحمل «المحمدعلي» من أمّها)
    when p_husband is null and p_mother is not null
         and exists (select 1 from public.women_members m
                     join public.profiles f on f.id = m.parent_id
                     where m.id = p_mother
                       and not exists (select 1 from public.profiles mh where mh.id = m.husband_id)) then true
    -- «المحمدعلي» بلا أب: من العائلة على الأغلب — تُربط بأبيها، لا تُعلَّم
    when replace(coalesce(p_name, ''), ' ', '') like '%المحمدعلي%' then null
    -- زوجة بلا أب في الشجرة
    when p_husband is not null then true
    else null
  end
$$;

revoke all on function private.women_outside_female(uuid, uuid, uuid, text) from public;

create or replace function private.women_outside_female_flag()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v boolean;
begin
  if lower(coalesce(new.gender, '')) <> 'female' then
    return new;
  end if;
  v := private.women_outside_female(new.parent_id, new.husband_id, new.mother_id,
                                    coalesce(nullif(new.full_name, ''), new.first_name));
  if v is not null then
    new.is_outside_family := v;
  end if;
  return new;
end;
$$;

revoke all on function private.women_outside_female_flag() from public;

-- الإضافات الجديدة (زوجة من خارج العائلة من أي تطبيق) والتعديلات على الأب/الزوج/الأم/الاسم
drop trigger if exists trg_women_outside_flag on public.women_members;
create trigger trg_women_outside_flag
  before insert or update of parent_id, husband_id, mother_id, full_name, first_name, gender
  on public.women_members
  for each row execute function private.women_outside_female_flag();

-- من عُلِّمت الحين (للمراجعة والتراجع)
create table if not exists private.outside_women_backfill (
  id uuid primary key,
  flagged_at timestamptz not null default now()
);

insert into private.outside_women_backfill (id)
select w.id
from public.women_members w
where lower(coalesce(w.gender, '')) = 'female'
  and not w.is_outside_family
  and private.women_outside_female(w.parent_id, w.husband_id, w.mother_id,
                                   coalesce(nullif(w.full_name, ''), w.first_name)) is true
on conflict (id) do nothing;

update public.women_members w
set is_outside_family = true
from private.outside_women_backfill b
where b.id = w.id
  and not w.is_outside_family;
