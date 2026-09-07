begin;
-- Diagnostic codes only: no free text, URLs, stack traces or member content.
create table public.app_diagnostic_events (
  reporter_id uuid not null references auth.users(id) on delete cascade,
  hour_bucket timestamptz not null,
  feature text not null,
  code text not null,
  app_version text not null,
  occurrences int not null default 1 check (occurrences between 1 and 30),
  first_seen timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  primary key(reporter_id,hour_bucket,feature,code,app_version)
);
create index app_diagnostic_events_last_seen on public.app_diagnostic_events(last_seen);
create table public.app_diagnostic_reviews (
  feature text not null, code text not null, app_version text not null,
  reviewed_through timestamptz not null,
  primary key(feature,code,app_version)
);
alter table public.app_diagnostic_events enable row level security;
alter table public.app_diagnostic_reviews enable row level security;
revoke all on public.app_diagnostic_events, public.app_diagnostic_reviews from public,anon,authenticated;

create function public.report_app_diagnostic(p_feature text,p_code text,p_app_version text)
returns boolean language plpgsql security definer set search_path=public as $$
declare me uuid := auth.uid(); bucket timestamptz := date_trunc('hour',now());
begin
  if me is null or not coalesce(public.is_approved_member(),false) then
    raise exception 'not_authorized' using errcode='42501';
  end if;
  if p_feature is null or p_feature not in ('news','members','notifications','media','auth','settings','diwaniyas','projects','admin','app')
    or p_code is null or p_code not in ('operation_failed','fetch_failed','offline','timeout','permission_denied')
    or p_app_version is null or p_app_version !~ '^[0-9]+([.][0-9]+){0,3}[(][0-9]+[)]$' or length(p_app_version)>32 then
    raise exception 'invalid_diagnostic';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('diagnostic:'||me::text,0));
  if (select coalesce(sum(occurrences),0) from public.app_diagnostic_events where reporter_id=me and hour_bucket=bucket)>=30 then return false; end if;
  insert into public.app_diagnostic_events(reporter_id,hour_bucket,feature,code,app_version)
  values(me,bucket,p_feature,p_code,p_app_version)
  on conflict(reporter_id,hour_bucket,feature,code,app_version) do update
    set occurrences=app_diagnostic_events.occurrences+1,last_seen=now();
  return true;
end $$;

create function public.app_diagnostics_dashboard()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb; jobs jsonb := '[]'; dispatch_ok boolean := false;
begin
  if coalesce(public.current_user_role(),'') not in ('owner','admin') then
    raise exception 'not_authorized' using errcode='42501';
  end if;
  with grouped as (
    select e.feature,e.code,e.app_version,sum(e.occurrences)::int as occurrences,
      min(e.first_seen) as first_seen,max(e.last_seen) as last_seen,
      max(e.last_seen)>coalesce(r.reviewed_through,'-infinity'::timestamptz) as needs_review
    from public.app_diagnostic_events e left join public.app_diagnostic_reviews r
      using(feature,code,app_version)
    where e.last_seen>now()-interval '7 days'
    group by e.feature,e.code,e.app_version,r.reviewed_through
  ) select jsonb_build_object(
    'total_occurrences',coalesce((select sum(occurrences) from grouped),0),
    'open_groups',(select count(*) from grouped where needs_review),
    'errors',coalesce((select jsonb_agg(to_jsonb(g) order by needs_review desc,last_seen desc)
      from (select * from grouped order by needs_review desc,last_seen desc limit 100) g),'[]'),
    'checked_at',now()) into result;
  if to_regclass('cron.job_run_details') is not null then
    execute $q$select coalesce(jsonb_agg(jsonb_build_object('name',j.jobname,'status',coalesce(r.status,'not_run'),'last_run',r.end_time) order by j.jobname),'[]')
      from cron.job j left join lateral(select status,end_time from cron.job_run_details
        where jobid=j.jobid and status in ('succeeded','failed') order by start_time desc,runid desc limit 1) r on true
      where j.active$q$ into jobs;
    execute $q$select exists(select 1 from cron.job j join cron.job_run_details r using(jobid)
      where j.jobname='dispatch-scheduled-notifications' and j.active and r.status='succeeded'
      and r.end_time>now()-interval '5 minutes')$q$ into dispatch_ok;
  end if;
  return result||jsonb_build_object('jobs',jobs,'dispatch_healthy',dispatch_ok);
end $$;

create function public.review_app_diagnostic(p_feature text,p_code text,p_app_version text,p_seen_at timestamptz)
returns void language plpgsql security definer set search_path=public as $$
declare cutoff timestamptz;
begin
  if coalesce(public.current_user_role(),'') not in ('owner','admin') then
    raise exception 'not_authorized' using errcode='42501';
  end if;
  select least(max(last_seen),p_seen_at) into cutoff from public.app_diagnostic_events
    where feature=p_feature and code=p_code and app_version=p_app_version;
  if cutoff is null or p_seen_at is null then raise exception 'diagnostic_not_found'; end if;
  insert into public.app_diagnostic_reviews values(p_feature,p_code,p_app_version,cutoff)
  on conflict(feature,code,app_version) do update
    set reviewed_through=greatest(app_diagnostic_reviews.reviewed_through,excluded.reviewed_through);
end $$;
revoke all on function public.report_app_diagnostic(text,text,text),public.app_diagnostics_dashboard(),public.review_app_diagnostic(text,text,text,timestamptz) from public,anon;
grant execute on function public.report_app_diagnostic(text,text,text),public.app_diagnostics_dashboard(),public.review_app_diagnostic(text,text,text,timestamptz) to authenticated;
-- Server-side retention only; no periodic Codex monitoring is created.
do $$ begin
  if exists(select 1 from pg_extension where extname='pg_cron') then
    perform cron.schedule('cleanup-app-diagnostics','20 4 * * *',
      $job$delete from public.app_diagnostic_events where last_seen<now()-interval '30 days';
      delete from public.app_diagnostic_reviews where reviewed_through<now()-interval '30 days';$job$);
  end if;
end $$;
commit;
