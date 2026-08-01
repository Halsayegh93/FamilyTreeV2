-- مُستخرَجة من سجل الإنتاج (supabase_migrations.schema_migrations)
-- كانت مطبَّقة على القاعدة لكن ملفها مفقود من المستودع.

-- ١) سياستا إدراج مفتوحتان (WITH CHECK = true) كانتا تُبطلان شرط الملكية:
-- السياسات في PostgreSQL تُجمع بـ«أو»، فوجود واحدة true يجعل أي أحد
-- يُدرج ديوانية/مشروعاً باسم عضو آخر. نحذفهما وتبقى سياسات الملكية.
drop policy if exists diwaniyas_insert on public.diwaniyas;
drop policy if exists projects_insert  on public.projects;

-- ٢) تثبيت search_path لدوال قديمة — يمنع اختطافها بجدول/دالة مزروعة
-- في مخطط آخر ضمن مسار البحث.
alter function public.trg_profiles_normalize_phone()  set search_path = public;
alter function public.normalize_kuwait_phone(text)    set search_path = public;
alter function public.normalize_phone_trigger()       set search_path = public;
alter function public.normalize_profile_names()       set search_path = public;;
