-- ═══════════════════════════════════════════════════════════════════════════
-- إصلاح أمني حرج: تسريب RLS للمفتاح العام (anon)
-- المفتاح العام (يُشحن داخل التطبيق) كان يقرأ profiles/هواتف/admin_requests/
-- notifications/news بدون تسجيل دخول، وبعض السياسات القديمة (USING true) كانت
-- تسمح بالكتابة/الحذف للجميع. السبب: سياسات قديمة متساهلة لم تُحذف، وهي تُدمج
-- (OR) مع السياسات المقيّدة فيغلب المتساهل.
--
-- الإصلاح: حذف السياسات الواسعة الـ 10، + سياسة حذف مقيّدة بديلة لـ admin_requests،
-- + سياسة RESTRICTIVE تتطلب تسجيل دخول على الجداول الأربعة (تُدمج AND مع كل شي،
-- فتحجب anon تماماً دون تغيير سلوك المستخدمين المسجّلين).
-- ═══════════════════════════════════════════════════════════════════════════

-- 1) حذف السياسات الواسعة المتساهلة (USING/CHECK = true, TO public)
drop policy if exists "Authenticated users can view all profiles" on public.profiles;
drop policy if exists "الكل يشاهد البيانات" on public.profiles;
drop policy if exists "Allow system to link profiles" on public.profiles;

drop policy if exists "admin_requests_select" on public.admin_requests;
drop policy if exists "admin_requests_insert" on public.admin_requests;
drop policy if exists "admin_requests_update" on public.admin_requests;
drop policy if exists "admin_requests_delete" on public.admin_requests;

drop policy if exists "الجميع يشاهد الأخبار" on public.news;
drop policy if exists "المدراء فقط يضيفون أخبار" on public.news;
drop policy if exists "news_delete" on public.news;

-- 2) بديل مقيّد لحذف admin_requests (الموافقة/الرفض تحذف الصف) — كان الوحيد للحذف
drop policy if exists "admin_requests_delete_moderator" on public.admin_requests;
create policy "admin_requests_delete_moderator" on public.admin_requests
  for delete
  using (public.current_user_role() = any (array['supervisor','monitor','admin','owner']));

-- 3) سياسة RESTRICTIVE: لا وصول بدون تسجيل دخول (تحجب anon على الجداول الأربعة)
--    RESTRICTIVE تُدمج AND مع السياسات الأخرى → المستخدم المسجّل لا يتأثر،
--    و anon (auth.uid() = null) يُحجب من القراءة والكتابة.
do $$
declare t text;
begin
  foreach t in array array['profiles','admin_requests','notifications','news']
  loop
    execute format('drop policy if exists %I on public.%I', 'require_authenticated_'||t, t);
    execute format(
      'create policy %I on public.%I as restrictive for all to public '
      'using (auth.uid() is not null) with check (auth.uid() is not null)',
      'require_authenticated_'||t, t);
  end loop;
end $$;
