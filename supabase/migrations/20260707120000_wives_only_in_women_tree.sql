-- ═══════════════════════════════════════════════════════════════════════════
-- الزوجات تظهر في شجرة النساء فقط — 2026-07-07
--
-- المشكلة: إضافة الزوجة من الملف الشخصي/تفاصيل العضو كانت تُدرجها في profiles
-- (husband_id) فتظهر باسمها في الشجرة الرئيسية. المطلوب: أسماء الزوجات تظهر
-- في شجرة النساء (women_members) فقط.
--
-- الإصلاح:
--   1) إخفاء زوجات profiles الحاليات (أنثى + husband_id + بلا أب في الشجرة)
--      من الشجرة الرئيسية عبر is_hidden_from_tree — بدون حذف، فتبقى روابط
--      mother_id للأبناء وبيانات التفاصيل سليمة.
--   2) عكسهنّ لشجرة النساء بنفس المعرف (نمط الانعكاس المعتمد في
--      mirror_profile_to_women) مع حمل رابط الزوج ورابط أمومة الأبناء.
--   3) trigger يفعل الأمرين تلقائياً لأي زوجة تُدرج في profiles مستقبلاً
--      (من نسخ تطبيق قديمة أو أي منصة) — فيبقى السلوك موحّداً.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── 1) عكس زوجة من profiles إلى شجرة النساء ────────────────────────────────
create or replace function public.mirror_profile_wife_to_women(p_wife_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  w public.profiles%rowtype;
begin
  select * into w from public.profiles where id = p_wife_id;
  if w.id is null
     or lower(coalesce(w.gender, '')) <> 'female'
     or w.husband_id is null then
    return;
  end if;

  insert into public.women_members (
    id, first_name, full_name, husband_id, gender,
    is_deceased, birth_date, death_date,
    sort_order, photo_url, avatar_url
  ) values (
    w.id,
    coalesce(w.first_name, ''),
    coalesce(nullif(w.full_name, ''), w.first_name, ''),
    -- الزوج موجود بنفس المعرف في شجرة النساء (انعكاس الذكور) — وإلا بلا رابط
    (select wm.id from public.women_members wm where wm.id = w.husband_id),
    'female',
    coalesce(w.is_deceased, false),
    w.birth_date,
    w.death_date,
    coalesce(w.sort_order, 0),
    w.photo_url,
    w.avatar_url
  )
  on conflict (id) do nothing;
end;
$$;

-- ─── 2) trigger: أي زوجة تدخل profiles → تُخفى من الشجرة الرئيسية وتنعكس ─────
create or replace function public.trg_profiles_wife_hidden_and_mirrored()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- زوجة من خارج العائلة فقط (بلا أب) — بنت العائلة المرتبطة كزوجة تبقى
  -- عقدة طبيعية في الشجرة تحت أبيها.
  if lower(coalesce(new.gender, '')) = 'female'
     and new.husband_id is not null
     and new.father_id is null then
    new.is_hidden_from_tree := true;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_wife_hidden on public.profiles;
create trigger profiles_wife_hidden
  before insert or update of husband_id on public.profiles
  for each row
  execute function public.trg_profiles_wife_hidden_and_mirrored();

create or replace function public.trg_profiles_wife_mirror_after()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if lower(coalesce(new.gender, '')) = 'female'
     and new.husband_id is not null
     and new.father_id is null then
    perform public.mirror_profile_wife_to_women(new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_wife_mirror on public.profiles;
create trigger profiles_wife_mirror
  after insert or update of husband_id on public.profiles
  for each row
  execute function public.trg_profiles_wife_mirror_after();

-- ─── 3) إصلاح بيانات: الزوجات الحاليات في profiles ──────────────────────────
do $$
declare
  w record;
  v_count int := 0;
begin
  for w in
    select id from public.profiles p
    where lower(coalesce(p.gender, '')) = 'female'
      and p.husband_id is not null
      and p.father_id is null
  loop
    -- عكس للنساء ثم إخفاء من الشجرة الرئيسية
    perform public.mirror_profile_wife_to_women(w.id);
    update public.profiles
       set is_hidden_from_tree = true
     where id = w.id
       and coalesce(is_hidden_from_tree, false) = false;
    v_count := v_count + 1;
  end loop;
  raise notice '[WIVES] عولجت % زوجة/زوجات (إخفاء + انعكاس لشجرة النساء)', v_count;
end $$;

-- ─── 4) حمل روابط الأمومة للأبناء المنعكسين في شجرة النساء ──────────────────
-- ابن في profiles أمه (mother_id) زوجة منعكسة → نسجل الأمومة نفسها في
-- women_members (الابن منعكس بنفس المعرف).
update public.women_members c
   set mother_id = p.mother_id
  from public.profiles p
 where p.id = c.id
   and p.mother_id is not null
   and c.mother_id is null
   and exists (select 1 from public.women_members m where m.id = p.mother_id);
