-- «المؤشرات» ليست للمراقب (طلب المالك ٢٠٢٦-١٠-٢٤): تقرير الموافقات (approvals_report) للمالك والمدير فقط — كان المراقب
-- يقرؤه أيضاً (بيته الوحيد «المؤشرات ← الموافقات»، ورقم «هذا الأسبوع» فيها). مستقلّ عن 20261025100000 ليوافق عليه المالك
-- وحده. طُبِّق على السيرفر الحي ٢٠٢٦-١٠-٢٥. التراجع: supabase/rollback/20261025100100_insights_owner_admin_only_rollback.sql
-- التجربة المحلية: cd supabase/tests/family_links && node owner_only_system_areas.test.mjs
-- التعريف الحي وقت الكتابة: approvals_report(timestamptz,timestamptz) md5 f2a84524782fd2593849b1ac333b70c3
-- (الشرط وحده يُستبدل، والترحيل يفشل إن لم يوجد مرة واحدة بالضبط). باقي «المؤشرات» (app_usage_stats/trend/engagement)
-- للمالك والمدير أصلاً؛ و`app_usage_members` يبقى للمراقب — صفحة «العائلة» تقرؤه (المسجّلون/المقيّدون).

do $patch$
declare
  d text;
  n int;
  v_old text := $o$not in ('owner', 'admin', 'monitor')$o$;
  v_new text := $n$not in ('owner', 'admin')$n$;
begin
  d := pg_get_functiondef('public.approvals_report(timestamptz,timestamptz)'::regprocedure);
  n := (length(d) - length(replace(d, v_old, ''))) / length(v_old);
  if n <> 1 then
    raise exception 'insights_owner_admin_only: expected the old text once, found % (the live function changed?)', n;
  end if;
  execute replace(d, v_old, v_new);
end
$patch$;
