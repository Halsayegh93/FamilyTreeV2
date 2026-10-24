-- تراجع 20261020190000_kwtsms_daily_check_and_suspicious: يوقف المهمة اليومية، يحذف kwtsms_balance_check و
-- kwtsms_daily_balance_job، يعيد log_login_attempt كما هي على السيرفر الحي حرفياً (pg_get_functiondef، قراءة فقط
-- ٢٠٢٦-١٠-٢٠، md5 e2df85b708ca82e8034b169f5b1882cc — يُفحص في tests/family_links/kwtsms_daily_check.test.mjs)،
-- ويحذف عمود login_attempts.alerted. الإشعارات التي خرجت (sms_balance_low / sms_suspicious) تبقى.
-- الترتيب: هذا الملف أولاً ثم حذف الدالة الطرفية kwtsms-cron (لو بقيت بلا الدالتين: نداءاتها ترجع 503 بلا أثر).
-- يعمل أيضاً على قاعدة لم يُطبَّق عليها الترحيل (كل حذف مشروط).

-- ═══ ١) الجدولة ═══
do $$
begin
  if exists (select 1 from cron.job where jobname = 'kwtsms-daily-balance') then
    perform cron.unschedule('kwtsms-daily-balance');
  end if;
end $$;

-- ═══ ٢) الدالتان الجديدتان ═══
drop function if exists public.kwtsms_daily_balance_job();
drop function if exists public.kwtsms_balance_check(numeric);

-- ═══ ٣) log_login_attempt كما في الحي حرفياً ═══
CREATE OR REPLACE FUNCTION public.log_login_attempt(p_phone text, p_outcome text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_keep int;
begin
  if p_phone is null or p_phone !~ '^965[4569][0-9]{7}$'
     or p_outcome is null or p_outcome not in ('sent', 'failed', 'unknown', 'blocked', 'test') then
    raise exception 'Invalid login attempt' using errcode = '22023';
  end if;
  insert into public.login_attempts (phone, profile_id, outcome)
  values (p_phone, public.login_attempt_profile_id(p_phone), p_outcome);
  select a.login_attempts_retention_days into v_keep
    from public.app_settings a order by a.updated_at desc limit 1;
  delete from public.login_attempts
   where id in (select a.id from public.login_attempts a
                 where a.created_at < now() - make_interval(days => coalesce(v_keep, 30))
                 order by a.created_at limit 200);
end;
$function$;
revoke all on function public.log_login_attempt(text, text) from public, anon, authenticated;
grant execute on function public.log_login_attempt(text, text) to service_role;

-- ═══ ٤) العمود ═══
alter table public.login_attempts drop column if exists alerted;
