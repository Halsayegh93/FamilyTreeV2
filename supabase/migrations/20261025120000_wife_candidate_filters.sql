-- ترشيح قائمة «إضافة زوجة» من العائلة (طلب المالك ٢٠٢٦-١٠-٢٥: المتزوجة، ومن عمرها أقل من ١٨، والمولودة توّاً لا يظهرن)
-- — الأرقام على السيرفر (قاعدة «من السيرفر»: تتغيّر بلا بناء تطبيق؛ طُبِّق بموافقة المالك «نعم» ٢٠٢٦-١٠-٢٥).
-- التطبيق يقرؤها من app_config() وافتراضه نفس القيم إن غابت. التراجع: supabase/rollback/20261025120000_wife_candidate_filters_rollback.sql
--   • wife_candidate_min_age (int، ١٨): لا تظهر من عمرها أقل من هذا حين يُعرف تاريخ ميلادها.
--   • wife_candidate_recent_months (int، ١٢): لا تظهر من أُضيفت خلال هذه الأشهر بلا تاريخ ميلاد (غالباً مولودة جديدة). ٠ = بلا هذا الشرط.

insert into public.app_config (key, value, default_value, kind, min_value, max_value, category, label_ar, help_ar, rules, is_public, sort)
values
  ('wife_candidate_min_age', '18'::jsonb, '18'::jsonb, 'int', 12, 30, 'tree',
   'أقل عمر لمرشّحة الزوجة (سنوات)',
   'قائمة «إضافة زوجة» من العائلة لا تُظهر من عمرها أقل من هذا (حين يُعرف تاريخ ميلادها).',
   '{}'::jsonb, false, 60),
  ('wife_candidate_recent_months', '12'::jsonb, '12'::jsonb, 'int', 0, 60, 'tree',
   'إخفاء المضافات حديثاً بلا تاريخ ميلاد (أشهر)',
   'من أُضيفت خلال هذه الأشهر بلا تاريخ ميلاد (غالباً مولودة جديدة) لا تظهر في قائمة الزوجة. ٠ = بلا هذا الشرط.',
   '{}'::jsonb, false, 61)
on conflict (key) do nothing;
