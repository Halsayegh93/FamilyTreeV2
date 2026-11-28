-- «تصميم إعلان» من السيرفر (طلب المالك ٢٠٢٦-١١-٠٨ «كل شي يكون من السيرفر»)
-- مطبَّق ٢٠٢٦-١١-٠٨ (بموافقة المالك «نعم كمّل»).
--
-- مفتاح واحد JSON يقرأه التطبيق (OccasionDesignerConfig.swift): إخفاء/ترتيب/اسم كل إعلان، إخفاء نموذج ١/٢/٣،
-- نموذج ٤ (تصميمه كله هنا — OccasionModel4View.swift)، ونصوص الاختيارات (البيانات) لكل إعلان ونموذج.
-- {} = التطبيق كما هو. النسخ القديمة من التطبيق ما تقرأه.
insert into public.app_config (key, value, default_value, kind, category, label_ar, help_ar, is_public, sort, min_value, max_value)
values
  ('occasion_designer', '{}'::jsonb, '{}'::jsonb, 'json', 'news',
   'تصميم إعلان (الإعلانات والنماذج والنصوص)',
   'order: ترتيب الإعلانات · templates.<id>: {hidden, title, models:["m3"]} · models.m1|m2|m3: {hidden, title, subtitle} · models.m4: {title, subtitle, layouts} (تصميم نموذج ٤) · lists: نصوص الاختيارات (openings.<id>، duas.<id>.m|f، deathLeads.m|f، cemeteries …). {} = كما في التطبيق.',
   false, 60, null, null)
on conflict (key) do nothing;
