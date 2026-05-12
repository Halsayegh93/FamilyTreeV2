-- ════════════════════════════════════════════════════════════════════════
-- Trigger: عند تعديل اسم عضو، يعيد بناء full_name لكل ذرّيته تلقائياً
--
-- المشكلة: full_name لكل عضو هو first_name + سلسلة آباءه. لو غيّر المالك
-- اسم "أمير" إلى "علي"، أبناء أمير وأحفاده فيهم اسمه القديم في full_name.
--
-- الحلّ على السيرفر: AFTER UPDATE trigger يعيد البناء عبر الذرّية كاملة.
-- يضمن العمل بغض النظر عن المصدر (iOS, web, SQL مباشر، أي client مستقبلي).
--
-- تطابق الـtrigger مع منطق العميل:
--   child.full_name = child.first_name || ' ' || parent.full_name
--
-- ملاحظة: التحديث الذي يفعّله الـtrigger يفعّل نفسه على الأبناء — كل
-- مستوى ينتشر للمستوى الذي تحته بشكل طبيعي بدون recursion يدوي.
-- ════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_cascade_full_name_to_children()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec record;
  new_child_name text;
BEGIN
  -- نتحرّك فقط لو full_name أو first_name تغيّرا فعلاً
  IF (NEW.full_name IS NOT DISTINCT FROM OLD.full_name)
     AND (NEW.first_name IS NOT DISTINCT FROM OLD.first_name) THEN
    RETURN NEW;
  END IF;

  -- لكل ابن مباشر: نبني full_name الجديد ونحدّث
  -- التحديث على كل ابن يفعّل نفس الـtrigger له، فينتشر تلقائياً للأحفاد
  FOR rec IN
    SELECT id, first_name
      FROM public.profiles
     WHERE father_id = NEW.id
  LOOP
    new_child_name := COALESCE(NULLIF(BTRIM(rec.first_name), ''), '')
                      || ' ' || COALESCE(NEW.full_name, '');
    new_child_name := BTRIM(new_child_name);

    -- نحدّث فقط لو الاسم الجديد فعلاً مختلف (نتجنّب ضربة DB غير لازمة)
    UPDATE public.profiles
       SET full_name = new_child_name
     WHERE id = rec.id
       AND full_name IS DISTINCT FROM new_child_name;
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cascade_full_name_to_children ON public.profiles;

CREATE TRIGGER trg_cascade_full_name_to_children
  AFTER UPDATE OF full_name, first_name ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_cascade_full_name_to_children();

COMMENT ON FUNCTION public.fn_cascade_full_name_to_children() IS
  'يعيد بناء full_name لكل أبناء العضو عند تغيير اسمه. ينتشر للأحفاد عبر تكرار الـtrigger طبيعياً.';

COMMENT ON TRIGGER trg_cascade_full_name_to_children ON public.profiles IS
  'Cascade الاسم الكامل للذرّية تلقائياً — يضمن اتساق full_name من السيرفر بدون اعتماد على الـclient.';
