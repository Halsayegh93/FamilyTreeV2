-- طلب المالك ٢٠٢٦-١١-٠٥ «نبي نخليه لي عمر ١٣ مقبول»: من بلغ ١٣ يتفعّل حسابه بموافقة الإدارة فقط.
-- أقل من ١٣ يبقى مرفوضاً (hint = under_13). دوال وجدول موافقة ولي الأمر تبقى بلا مسار يطلبها.
-- نص الشروط (app_config.legal_content) غير داخل في هذا الترحيل.
-- التراجع: supabase/rollback/20261105130000_accept_from_13_no_guardian_rollback.sql
do $mig$
declare
  d text;
  s int;
  e int;
begin
  d := pg_get_functiondef('public.trg_profiles_age_rules()'::regprocedure);
  s := position('elsif not public.has_guardian_consent(new.id) then' in d);
  if s = 0 then raise exception 'anchor: trg_profiles_age_rules'; end if;
  e := position('end if;' in substring(d from s));
  d := left(d, s - 1) || substring(d from s + e - 1);
  d := replace(d, 'and a is not null and a < 18 and public.profile_has_login(new.id)',
                  'and a is not null and a < 13 and public.profile_has_login(new.id)');
  execute d;

  d := pg_get_functiondef('public.merge_member_into_tree(uuid,uuid)'::regprocedure);
  s := position('  if public.age_years(coalesce(v_new.birth_date, v_tree.birth_date)) between 13 and 17' in d);
  e := position('  -- ─── حماية: ملف المالك لا يُدمج' in d);
  if s = 0 or e = 0 or e < s then raise exception 'anchor: merge_member_into_tree'; end if;
  d := left(d, s - 1) || substring(d from e);
  d := replace(d, 'لا حساب دون ١٣، ومن ١٣ إلى ١٧ بعد موافقة ولي الأمر', 'لا حساب دون ١٣');
  execute d;
end
$mig$;
