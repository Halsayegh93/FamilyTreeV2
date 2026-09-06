begin;
create or replace function public.operational_health()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare cron_failures int := 0; http_failures int := 0; pending_deletions int;
begin
  if public.current_user_role() not in ('owner','admin') or public.current_user_role() is null then raise exception 'not_authorized' using errcode='42501'; end if;
  if to_regclass('cron.job_run_details') is not null then
    execute $q$select count(*)::int from cron.job_run_details where status='failed' and start_time>now()-interval '24 hours'$q$ into cron_failures;
  end if;
  if to_regclass('net._http_response') is not null then
    execute $q$select count(*)::int from net._http_response where created>now()-interval '24 hours' and (status_code>=400 or timed_out or error_msg is not null)$q$ into http_failures;
  end if;
  select count(*)::int into pending_deletions from public.account_deletion_jobs j
    where j.created_at<now()-interval '15 minutes' and exists(select 1 from auth.users u where u.id=j.auth_user_id);
  return jsonb_build_object('cron_failures',cron_failures,'http_failures',http_failures,'pending_deletions',pending_deletions,'checked_at',now());
end $$;
revoke all on function public.operational_health() from public,anon;
grant execute on function public.operational_health() to authenticated;
commit;
