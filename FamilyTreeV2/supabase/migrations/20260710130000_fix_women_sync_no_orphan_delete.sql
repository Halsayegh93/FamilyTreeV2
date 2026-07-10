-- ═══════════════════════════════════════════════════════════════════════════
-- إصلاح فقدان بيانات: trigger مزامنة الرجال لشجرة النساء كان يحذف عقدة المستخدم
-- في فرع else (عند father_id NULL أو gender != male)، والحذف يُفعّل ON DELETE
-- SET NULL على husband_id/parent_id/mother_id فيفصل الزوجة/البنات/الأم.
--
-- الإصلاح: لا تحذف العقدة إذا كان لها تابعون (زوجة/أبناء/أم) في شجرة النساء —
-- بدل الحذف، حدّث حقولها فقط. الحذف يبقى فقط للمرايا اليتيمة (بلا تابعين).
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.sync_profile_update_to_women()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- يتأهّل كابن ذكر له أب → تأكّد من وجود/تحديث المرآة (كما كان).
  if new.father_id is not null
     and (new.gender is null or lower(new.gender) = 'male') then
    insert into public.women_members (
      id, first_name, full_name, parent_id, gender,
      is_deceased, birth_date, death_date, is_hidden_from_tree,
      sort_order, photo_url, avatar_url
    ) values (
      new.id,
      coalesce(new.first_name, ''),
      coalesce(nullif(new.full_name, ''), new.first_name, ''),
      new.father_id,
      'male',
      coalesce(new.is_deceased, false),
      new.birth_date, new.death_date,
      coalesce(new.is_hidden_from_tree, false),
      coalesce(new.sort_order, 0),
      new.photo_url, new.avatar_url
    )
    on conflict (id) do update set
      first_name          = excluded.first_name,
      full_name           = excluded.full_name,
      parent_id           = excluded.parent_id,
      is_deceased         = excluded.is_deceased,
      birth_date          = excluded.birth_date,
      death_date          = excluded.death_date,
      is_hidden_from_tree = excluded.is_hidden_from_tree;
  else
    -- لم يعد ابناً ذكراً له أب (مثلاً أُزيل الأب، أو هو جذر فرع father_id NULL).
    -- ⚠️ لا تحذف العقدة إذا لها تابعون في شجرة النساء — الحذف يفصلهم نهائياً.
    if exists (
      select 1 from public.women_members w
      where w.husband_id = new.id
         or w.parent_id  = new.id
         or w.mother_id  = new.id
    ) then
      -- أبقِ العقدة (لحماية الزوجة/البنات/الأم) وحدّث حقولها فقط.
      update public.women_members set
        first_name          = coalesce(new.first_name, ''),
        full_name           = coalesce(nullif(new.full_name, ''), new.first_name, ''),
        is_deceased         = coalesce(new.is_deceased, false),
        birth_date          = new.birth_date,
        death_date          = new.death_date,
        is_hidden_from_tree = coalesce(new.is_hidden_from_tree, false)
      where id = new.id;
    else
      -- مرآة يتيمة بلا تابعين → حذفها آمن.
      delete from public.women_members where id = new.id;
    end if;
  end if;
  return new;
end;
$$;

-- ملاحظة: الـtrigger trg_sync_profile_update_to_women نفسه لم يتغيّر (نفس WHEN)،
-- فقط استُبدلت دالته أعلاه عبر create or replace.
