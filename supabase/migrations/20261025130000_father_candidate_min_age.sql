-- عمر الأب في قائمة «أبوها» (مسار الزوجة والأم) على السيرفر — موافقة المالك ٢٠٢٦-١٠-٢٥ «نعم ضيف بالسيرفر».
-- الحيّ يظهر أباً إن عُرف ميلاده وكان عمره ≥ هذا الرقم؛ المتوفّى وبلا ميلاد يظهران دائماً (التطبيق: WifeCandidateRules.canBeFather).
-- طُبِّق بـ٣٠ ثم عُدّل إلى ٣٥ بطلب المالك (UPDATE مباشر) — القيمة الحية ٣٥.
-- التراجع: supabase/rollback/20261025130000_father_candidate_min_age_rollback.sql
insert into public.app_config (key, value, default_value, kind, min_value, max_value, category, label_ar, help_ar, rules, is_public, sort)
values
  ('father_candidate_min_age', '35'::jsonb, '35'::jsonb, 'int', 15, 70, 'tree', 'أقل عمر للأب في قائمة «أبوها» (سنوات)',
   'في إضافة الزوجة أو الأم من العائلة: الرجل الحيّ المعروف ميلاده لا يظهر أباً إن كان أصغر من هذا العمر. المتوفّى ومن بلا تاريخ ميلاد يظهران دائماً.',
   '{}'::jsonb, false, 62)
on conflict (key) do nothing;
