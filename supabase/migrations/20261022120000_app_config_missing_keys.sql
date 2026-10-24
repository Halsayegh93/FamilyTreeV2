-- القيم الست الناقصة في app_config على الحي (طُبّق 20261021110000 من نسخة سابقة بلا هذه الصفوف — ٢٠٢٦-١٠-٢٢).
-- نفس تعريفات الملف حرفياً؛ «حد تعديل الملف» يبدأ مطفأً حتى تنزل نسخ التطبيقات (قرار المالك ٢٠٢٦-١٠-٢٢).
-- لا يلمس أي مفتاح موجود (on conflict do nothing). التراجع: rollback/20261022120000_app_config_missing_keys_rollback.sql
insert into public.app_config (key, kind, value, default_value, min_value, max_value, max_length, category,
                               label_ar, help_ar, rules, is_public, sort)
select v.key, v.kind, v.def, v.def, v.min_value, v.max_value, v.max_length, v.category, v.label_ar, v.help_ar,
       v.rules::jsonb, v.is_public, v.sort
from (values
  ('profile_edit_limit_enabled', 'bool', 'true'::jsonb, null::numeric, null::numeric, null::integer, 'members',
   'حد تعديل الملف الشخصي',
   'مفعّل: بعد عدد التعديلات المباشرة يذهب تعديل العضو للإدارة. مطفأ: كل تعديلات العضو على ملفه تُحفظ مباشرة.',
   '{}', false, 10),
  ('profile_free_edits', 'int', '3', 0, 10, null, 'members',
   'عدد التعديلات المباشرة لكل حقل',
   'كم مرة يعدّل العضو بنفسه تاريخ ميلاده أو حالته الاجتماعية أو سيرته أو صورته أو رقمه قبل أن يحتاج موافقة الإدارة. صفر = كل تعديل للإدارة.',
   '{}', false, 20),
  ('terms_version', 'int', '1', 1, 1000, null, 'members',
   'نسخة شروط الاستخدام',
   'ارفع الرقم إذا تغيّرت الشروط، فيُطلب من كل الأعضاء الموافقة عليها مرة أخرى.',
   '{}', true, 30),
  ('age_bands', 'json', '[18, 30, 50, 70]', 1, 120, null, 'members',
   'الفئات العمرية',
   'حدود الفئات في المؤشرات والتقارير: [18, 30, 50, 70] تعني أقل من 18، 18–29، 30–49، 50–69، 70 وأكثر.',
   '{"items": "int", "min_items": 1, "max_items": 8, "ascending": true}', false, 70),
  ('branch_root_id', 'text', '""', null, null, 36, 'tree',
   'رأس الشجرة',
   'معرّف رأس الشجرة (عبدالله المحمدعلي). فارغ = يُعرف بالاسم كما اليوم.',
   '{"min_length": 0, "pattern": "^$|^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", "pattern_ar": "معرّف غير صالح — اتركه فارغاً أو اختر العضو"}',
   false, 10),
  ('branch_extra_heads', 'json',
   '[{"id": null, "name": "محمدعلي حسن المحمدعلي"}, {"id": null, "name": "علي عبدالمحسن المحمدعلي"}, {"id": null, "name": "محمدحسن احمد المحمدعلي"}, {"id": null, "name": "ابراهيم(العطار) المحمدعلي"}]',
   null, null, 80, 'tree',
   'الفروع الإضافية في «اختر فرعاً»',
   'فروع تظهر في القائمة الرئيسية بجانب أبناء رأس الشجرة (بحث الشجرة، مركز التقارير، سجل الأعضاء). الاسم هو المعروض؛ المعرّف يربطها بالشخص نفسه، وبلا معرّف تُعرف بالاسم كما اليوم.',
   '{"items": "branch_head", "max_items": 20}', false, 20)
) as v(key, kind, def, min_value, max_value, max_length, category, label_ar, help_ar, rules, is_public, sort)
on conflict (key) do nothing;

update public.app_config set value = 'false'::jsonb where key = 'profile_edit_limit_enabled';
