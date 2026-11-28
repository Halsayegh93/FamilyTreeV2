-- شجرة العائلة للرجال فقط (قاعدة المالك): البنت مكانها شجرة النساء (women_members) لا profiles.
-- مطبَّق على الحي ٢٠٢٦-١١-٢٧ بعد تجربة begin…rollback (١ و٤ رُفضا، ٢ و٣ و٥ و٦ و٧ مرّت)؛ تجربة node ٣٩/٣٩.
-- الآيفون يمنع إضافة أنثى (d585bb12، c9dc2d93)؛ هذا الحارس يفرضه على السيرفر لكل التطبيقات.
--
-- يُرفض (P0001، hint = family_tree_men_only) صف في profiles جنسه أنثى وله أب (father_id) —
-- إذا كان مخالفة جديدة فقط:
--   • الإدراج: أنثى + أب.
--   • التعديل: صار الجنس أنثى (وله أب)، أو تغيّر الأب لأنثى (من فارغ أو من أب آخر).
--   فالصفّان الموجودان (أنثى + أب، مخفيّتان: 7b67db57…، 8d96064c…) لا يُمسّان ما لم يغيّر أحد جنسهما أو أبيهما،
--   وفكّ الأب عنهما (father_id = null) مسموح.
-- لا يتأثر:
--   • حساب المرأة (تسجيل أنثى بلا أب) — لا أب.
--   • add_family_child — البنت تُكتب في women_members، والابن 'male' في profiles.
--   • move_child_gender — لا يكتب أنثى في profiles أصلاً (ينشئ عقدة في women_members ويحذف الصف)؛
--     العلم family.gender_move مسموح احتياطاً لو احتاجت الدالة لاحقاً: set_config('family.gender_move','on', true).
--   • apply_women_request — يكتب في women_members.
-- صيانة SQL مقصودة (بلا مستخدم فقط): select set_config('family.allow_female_profile','on', true);
-- التراجع: rollback/20261127130000_family_tree_men_only_rollback.sql
-- التجربة: cd supabase/tests/family_links && node family_tree_men_only.test.mjs

create or replace function private.family_tree_men_only()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if lower(btrim(coalesce(new.gender, ''))) <> 'female' or new.father_id is null then
    return new;
  end if;
  -- مخالفة قديمة لم تتغيّر (الجنس كان أنثى والأب نفسه) → تمر
  if tg_op = 'UPDATE'
     and lower(btrim(coalesce(old.gender, ''))) = 'female'
     and old.father_id is not distinct from new.father_id then
    return new;
  end if;
  if coalesce(current_setting('family.gender_move', true), '') = 'on' then
    return new;
  end if;
  if auth.uid() is null
     and coalesce(current_setting('family.allow_female_profile', true), '') = 'on' then
    return new;
  end if;
  raise exception 'شجرة العائلة للرجال فقط — أضف البنت في شجرة النساء'
    using errcode = 'P0001', hint = 'family_tree_men_only';
end;
$function$;

drop trigger if exists trg_zzzz_family_tree_men_only on public.profiles;
create trigger trg_zzzz_family_tree_men_only
  before insert or update of gender, father_id on public.profiles
  for each row execute function private.family_tree_men_only();
