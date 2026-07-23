-- ═══════════════════════════════════════════════════════════════════════════
-- تعبئة الرجال القدامى في شجرة النساء + ربط الزوجات بأزواجهنّ — 2026-07-07
--
-- المشكلة: شجرة النساء (women_members) تعرض الزوجات معلّقةً على أزواجهنّ عبر
-- husband_id. لكن مُحفِّز انعكاس الرجال (mirror_profile_to_women) يعمل فقط على
-- الإدراج الجديد ولم يُعبِّئ الرجال الموجودين مسبقاً. فالرجال القدامى (مثل أنور)
-- غير موجودين في women_members، وعند نقل زوجاتهم (ترحيل 20260707120000) لم تجد
-- الزوجة زوجاً تتعلّق به → لم تظهر في شجرة النساء.
--
-- الإصلاح:
--   1) تعبئة كل الرجال من profiles إلى women_members بنفس المعرّف (idempotent).
--      يعيد بناء سلسلة النسب الذكورية التي تتعلّق بها النساء.
--   2) ربط الزوجات المنعكسات بأزواجهنّ الآن بعد وجودهم (husband_id).
--   3) حمل روابط الأمومة للأبناء المنعكسين.
--   4) تحصين دالة انعكاس الزوجة: تضمن انعكاس الزوج أولاً مستقبلاً.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- ─── 1) تعبئة كل الرجال (سلسلة النسب) في شجرة النساء ─────────────────────────
-- نفس تعيين مُحفِّز mirror_profile_to_women، لكن للموجودين مسبقاً. يشمل الجدّ
-- الأعلى (father_id فارغ → parent_id فارغ) حتى تكتمل السلسلة حتى القمة.
insert into public.women_members (
  id, first_name, full_name, parent_id, gender,
  is_deceased, birth_date, death_date, is_hidden_from_tree,
  sort_order, photo_url, avatar_url
)
select
  p.id,
  coalesce(p.first_name, ''),
  coalesce(nullif(p.full_name, ''), p.first_name, ''),
  p.father_id,
  'male',
  coalesce(p.is_deceased, false),
  p.birth_date,
  p.death_date,
  coalesce(p.is_hidden_from_tree, false),
  coalesce(p.sort_order, 0),
  p.photo_url,
  p.avatar_url
from public.profiles p
where lower(coalesce(p.gender, '')) <> 'female'   -- الذكور (غير المحدَّد = ذكر)
  and coalesce(btrim(p.full_name), '') <> ''      -- أعضاء حقيقيون
on conflict (id) do nothing;

-- ─── 2) ربط الزوجات المنعكسات بأزواجهنّ ─────────────────────────────────────
-- الزوجة في women_members قد تكون husband_id فارغاً (وقت النقل لم يكن الزوج
-- موجوداً). الآن الزوج موجود → نربط.
update public.women_members w
   set husband_id = p.husband_id
  from public.profiles p
 where p.id = w.id
   and p.husband_id is not null
   and w.husband_id is null
   and exists (select 1 from public.women_members h where h.id = p.husband_id);

-- ─── 3) حمل روابط الأمومة للأبناء المنعكسين ─────────────────────────────────
update public.women_members c
   set mother_id = p.mother_id
  from public.profiles p
 where p.id = c.id
   and p.mother_id is not null
   and c.mother_id is null
   and exists (select 1 from public.women_members m where m.id = p.mother_id);

-- ─── 4) تحصين دالة انعكاس الزوجة: تضمن انعكاس الزوج أولاً ────────────────────
-- مستقبلاً: عند إضافة زوجة لرجل غير منعكس بعد، ننعكس الزوج تلقائياً قبلها
-- فلا تتكرر مشكلة «زوجة بلا زوج».
create or replace function public.mirror_profile_wife_to_women(p_wife_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  w public.profiles%rowtype;
  h public.profiles%rowtype;
begin
  select * into w from public.profiles where id = p_wife_id;
  if w.id is null
     or lower(coalesce(w.gender, '')) <> 'female'
     or w.husband_id is null then
    return;
  end if;

  -- تأكد أن الزوج موجود في شجرة النساء — وإلا انعكسه أولاً
  if not exists (select 1 from public.women_members wm where wm.id = w.husband_id) then
    select * into h from public.profiles where id = w.husband_id;
    if h.id is not null then
      insert into public.women_members (
        id, first_name, full_name, parent_id, gender,
        is_deceased, birth_date, death_date, is_hidden_from_tree,
        sort_order, photo_url, avatar_url
      ) values (
        h.id,
        coalesce(h.first_name, ''),
        coalesce(nullif(h.full_name, ''), h.first_name, ''),
        h.father_id,
        'male',
        coalesce(h.is_deceased, false),
        h.birth_date, h.death_date,
        coalesce(h.is_hidden_from_tree, false),
        coalesce(h.sort_order, 0),
        h.photo_url, h.avatar_url
      )
      on conflict (id) do nothing;
    end if;
  end if;

  insert into public.women_members (
    id, first_name, full_name, husband_id, gender,
    is_deceased, birth_date, death_date,
    sort_order, photo_url, avatar_url
  ) values (
    w.id,
    coalesce(w.first_name, ''),
    coalesce(nullif(w.full_name, ''), w.first_name, ''),
    (select wm.id from public.women_members wm where wm.id = w.husband_id),
    'female',
    coalesce(w.is_deceased, false),
    w.birth_date,
    w.death_date,
    coalesce(w.sort_order, 0),
    w.photo_url,
    w.avatar_url
  )
  on conflict (id) do update
    set husband_id = excluded.husband_id
    where public.women_members.husband_id is null;
end;
$$;

commit;
