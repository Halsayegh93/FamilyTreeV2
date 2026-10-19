-- members_masked للقراءة فقط (فحص الثغرات ٢٠٢٦-١٠-٠٤)
--
-- الواجهة members_masked يملكها postgres (يتجاوز RLS) وليست security_invoker، وهي
-- «قابلة للتحديث تلقائياً» بلا WITH CHECK OPTION، وكان لـ authenticated عليها
-- INSERT/UPDATE/DELETE. أي عضو مفعّل كان يقدر — عبر الواجهة — يعدّل أو يحذف صفوف
-- profiles لغيره متجاوزاً كل سياسات RLS (الاسم، الأب، الوفاة، الإخفاء، الصورة…)؛
-- المشغّلات وحدها كانت تمنع تغيير الدور والحالة.
--
-- التطبيقات (آيفون، أندرويد، الموقع) تقرأ من الواجهة فقط ولا تكتب عبرها — فسحب
-- صلاحية الكتابة لا يكسر شيئاً. القراءة كما هي.
-- التراجع: supabase/rollback/20261004120000_members_masked_read_only_rollback.sql

revoke insert, update, delete, truncate, references, trigger
  on public.members_masked from authenticated, anon;
