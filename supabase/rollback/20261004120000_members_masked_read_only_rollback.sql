-- تراجع: إرجاع صلاحيات الكتابة على members_masked كما كانت قبل ٢٠٢٦-١٠-٠٤
-- (يعيد الثغرة — لا يُستعمل إلا إذا تبيّن أن جزءاً من التطبيق يكتب عبر الواجهة)
grant insert, update, delete, truncate, references, trigger
  on public.members_masked to authenticated;
