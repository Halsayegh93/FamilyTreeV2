-- جدول الأرقام المحظورة
CREATE TABLE IF NOT EXISTS public.banned_phones (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_number TEXT NOT NULL UNIQUE,
  reason TEXT,
  banned_by UUID NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
  is_active BOOLEAN NOT NULL DEFAULT true
);

ALTER TABLE public.banned_phones ENABLE ROW LEVEL SECURITY;

-- المدير والمشرف يقدرون يشوفون
CREATE POLICY "banned_phones_select" ON public.banned_phones
FOR SELECT USING (public.current_user_role() IN ('admin', 'supervisor'));

-- المدير بس يقدر يضيف
CREATE POLICY "banned_phones_insert" ON public.banned_phones
FOR INSERT WITH CHECK (public.current_user_role() = 'admin');

-- المدير بس يقدر يعدّل
CREATE POLICY "banned_phones_update" ON public.banned_phones
FOR UPDATE USING (public.current_user_role() = 'admin');

-- المدير بس يقدر يحذف
CREATE POLICY "banned_phones_delete" ON public.banned_phones
FOR DELETE USING (public.current_user_role() = 'admin');

-- فهرس للبحث السريع عن الأرقام النشطة
CREATE INDEX IF NOT EXISTS idx_banned_phones_active
  ON public.banned_phones(phone_number) WHERE is_active = true;
