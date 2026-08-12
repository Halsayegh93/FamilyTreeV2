-- 🔴 إغلاق انتحال الدور: current_user_role كانت تثق بـuser_metadata وهو
-- قابل للكتابة من العميل (updateUser({data:{profile_id}})) — فأي عضو
-- يزعم أنه المالك ويحصل على صلاحياته في كل سياسة تستعملها.
-- app_metadata يكتبه service_role حصراً، وهو ما تعتمده سياسات النساء
-- منذ 20260716222452. تحقّق قبل التطبيق: صفر حسابات تعتمد user_metadata وحده.
create or replace function public.current_user_role()
returns text
language sql
stable
security definer
set search_path to 'public'
as $fn$
  select case when p.status = 'frozen' then 'frozen' else p.role end
  from public.profiles p
  where p.id = coalesce(
    nullif(auth.jwt() -> 'app_metadata' ->> 'profile_id', '')::uuid,
    auth.uid()
  )
$fn$;
