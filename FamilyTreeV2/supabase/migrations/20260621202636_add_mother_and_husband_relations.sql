-- علاقات الأم والزوجة (مطابقة لأسلوب father_id)
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS mother_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS husband_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL;

-- فهارس للبحث العكسي (أبناء الأم / زوجات الزوج)
CREATE INDEX IF NOT EXISTS idx_profiles_mother_id ON public.profiles(mother_id);
CREATE INDEX IF NOT EXISTS idx_profiles_husband_id ON public.profiles(husband_id);

COMMENT ON COLUMN public.profiles.mother_id IS 'أم العضو (تشير لعضوة أنثى) — يربط الأم بالأبناء';
COMMENT ON COLUMN public.profiles.husband_id IS 'للأنثى (الزوجة): معرّف زوجها — زوجات الرجل = من husband_id = هو';;
