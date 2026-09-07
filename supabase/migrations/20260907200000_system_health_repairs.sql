begin;

-- Fixed repair recipes, never arbitrary SQL supplied by a client.
create function public._system_health_job_spec(p_job_name text)
returns table(schedule text, commands text[], count_sql text, lock_sql text)
language sql immutable set search_path=public as $$
 select specs.schedule,specs.commands,specs.count_sql,specs.lock_sql from (values
 ('cleanup-old-join-requests','0 3 * * 3',
  array[$q$delete from public.join_requests where status in ('approved','rejected') and created_at < now()-interval '60 days'$q$],
  $q$select count(*)::int from public.join_requests where status in ('approved','rejected') and created_at < now()-interval '60 days'$q$,
  'lock table public.join_requests in share row exclusive mode'),
 ('cleanup-old-web-sessions','0 2 * * *',
  array[$q$delete from public.web_sessions where last_seen_at < now()-interval '30 days'$q$],
  $q$select count(*)::int from public.web_sessions where last_seen_at < now()-interval '30 days'$q$,
  'lock table public.web_sessions in share row exclusive mode'),
 ('cleanup-delivery-attempts','15 3 * * *',
  array[$q$delete from public.delivery_attempts where attempted_at < now()-interval '8 days'$q$],
  $q$select count(*)::int from public.delivery_attempts where attempted_at < now()-interval '8 days'$q$,
  'lock table public.delivery_attempts in share row exclusive mode'),
 ('cleanup-app-diagnostics','20 4 * * *',
  array[$q$delete from public.app_diagnostic_events where last_seen < now()-interval '30 days'$q$,
        $q$delete from public.app_diagnostic_reviews where reviewed_through < now()-interval '30 days'$q$],
  $q$select ((select count(*) from public.app_diagnostic_events where last_seen < now()-interval '30 days') + (select count(*) from public.app_diagnostic_reviews where reviewed_through < now()-interval '30 days'))::int$q$,
  'lock table public.app_diagnostic_events, public.app_diagnostic_reviews in share row exclusive mode')
 ) as specs(name,schedule,commands,count_sql,lock_sql) where name=p_job_name;
$$;
revoke all on function public._system_health_job_spec(text) from public,anon,authenticated;

create table public.system_health_repairs (
 request_id uuid primary key,
 actor_id uuid references auth.users(id) on delete set null,
 job_name text not null,
 status text not null check(status in ('succeeded','failed')),
 affected_rows int not null default 0,
 error_code text,
 completed_at timestamptz not null default clock_timestamp()
);
create index system_health_repairs_job_time on public.system_health_repairs(job_name,completed_at desc);
alter table public.system_health_repairs enable row level security;
revoke all on public.system_health_repairs from public,anon,authenticated;

create function public.system_health_repair_preview(p_job_name text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare spec record; eligible int; schema_needed boolean := false; job record;
begin
 if auth.uid() is null or coalesce(public.current_user_role(),'') not in ('owner','admin') then
  raise exception 'not_authorized' using errcode='42501';
 end if;
 select * into spec from public._system_health_job_spec(p_job_name);
 if not found then raise exception 'unsupported_repair'; end if;
 if to_regclass('cron.job') is null then raise exception 'scheduler_unavailable'; end if;
 select * into job from cron.job where jobname=p_job_name;
 if found and (job.username<>current_user or job.database<>current_database()) then raise exception 'job_owner_mismatch'; end if;
 if (select count(*) from cron.job where jobname=p_job_name)>1 then raise exception 'ambiguous_job'; end if;
 schema_needed := p_job_name='cleanup-old-join-requests' and not exists(
  select 1 from information_schema.columns where table_schema='public' and table_name='join_requests' and column_name='created_at');
 if schema_needed then eligible := 0; else execute spec.count_sql into eligible; end if;
 return jsonb_build_object('job_name',p_job_name,'eligible_rows',eligible,'can_run',eligible<=5000,
  'schema_repair_needed',schema_needed,'configuration_needs_repair',schema_needed or job.jobid is null or not job.active
    or job.schedule<>spec.schedule or btrim(regexp_replace(job.command,'[[:space:]]','','g'),';')<>btrim(regexp_replace(array_to_string(spec.commands,';'),'[[:space:]]','','g'),';'),
  'checked_at',now());
end $$;

create function public.repair_system_health_job(p_job_name text,p_request_id uuid,p_expected_rows int)
returns jsonb language plpgsql security definer set search_path=public set lock_timeout='5s' as $$
declare spec record; previous public.system_health_repairs; preview jsonb; eligible int;
 affected int := 0; step_count int; statement text; failure_code text; outcome text := 'succeeded'; repaired_job bigint;
begin
 if auth.uid() is null or coalesce(public.current_user_role(),'') not in ('owner','admin') then
  raise exception 'not_authorized' using errcode='42501';
 end if;
 if p_request_id is null or p_expected_rows is null or p_expected_rows<0 or p_expected_rows>5000 then raise exception 'invalid_repair_request'; end if;
 select * into spec from public._system_health_job_spec(p_job_name);
 if not found then raise exception 'unsupported_repair'; end if;
 -- Serialize identical request IDs as well as simultaneous repairs of one job.
 perform pg_advisory_xact_lock(hashtextextended('health-request:'||p_request_id::text,0));
 perform pg_advisory_xact_lock(hashtextextended('health-job:'||p_job_name,0));
 select * into previous from public.system_health_repairs where request_id=p_request_id;
 if found then
  if previous.job_name<>p_job_name or previous.actor_id is distinct from auth.uid() then raise exception 'request_conflict'; end if;
  return to_jsonb(previous)-'actor_id';
 end if;
 if exists(select 1 from public.system_health_repairs where job_name=p_job_name and completed_at>now()-interval '30 seconds') then raise exception 'repair_cooldown'; end if;
 preview := public.system_health_repair_preview(p_job_name);
 if not (preview->>'can_run')::boolean then raise exception 'repair_too_large'; end if;
 if exists(select 1 from cron.job j join cron.job_run_details r using(jobid) where j.jobname=p_job_name
   and r.status in ('starting','running','connecting','sending') and r.start_time>now()-interval '10 minutes') then raise exception 'job_running'; end if;
 -- Prevent a changing dataset between the confirmed count and the cleanup.
 execute spec.lock_sql;
 preview := public.system_health_repair_preview(p_job_name);
 eligible := (preview->>'eligible_rows')::int;
 if eligible<>p_expected_rows then raise exception 'preview_changed'; end if;
 begin
  if p_job_name='cleanup-old-join-requests' then
   -- Unknown legacy ages start now; never infer that legacy records are old.
   alter table public.join_requests add column if not exists created_at timestamptz not null default now();
  end if;
  -- Restore the reviewed recipe and normal cadence; this does not inject rows
  -- into cron.job_run_details. Manual execution is audited separately below.
  select cron.schedule(p_job_name,spec.schedule,array_to_string(spec.commands,E';\n')) into repaired_job;
  perform cron.alter_job(repaired_job,active:=true);
  foreach statement in array spec.commands loop
   execute statement;
   get diagnostics step_count = row_count;
   affected := affected + step_count;
  end loop;
  if affected<>eligible then raise exception 'repair_row_count_mismatch'; end if;
  if not exists(select 1 from cron.job where jobid=repaired_job and active and schedule=spec.schedule
    and command=array_to_string(spec.commands,E';\n')) then raise exception 'repair_verification_failed'; end if;
 exception when others then
  -- The whole repair/cleanup subtransaction rolls back on failure.
  outcome := 'failed'; failure_code := sqlstate; affected := 0;
 end;
 insert into public.system_health_repairs(request_id,actor_id,job_name,status,affected_rows,error_code)
 values(p_request_id,auth.uid(),p_job_name,outcome,affected,failure_code)
 returning * into previous;
 return to_jsonb(previous)-'actor_id';
end $$;

revoke all on function public.system_health_repair_preview(text),public.repair_system_health_job(text,uuid,int) from public,anon;
grant execute on function public.system_health_repair_preview(text),public.repair_system_health_job(text,uuid,int) to authenticated;

create or replace function public.app_diagnostics_dashboard()
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
    execute $q$with names as (
      select jobname as name from cron.job where active or jobname in ('cleanup-old-join-requests','cleanup-old-web-sessions','cleanup-delivery-attempts','cleanup-app-diagnostics')
      union select unnest(array['cleanup-old-join-requests','cleanup-old-web-sessions','cleanup-delivery-attempts','cleanup-app-diagnostics'])
    ) select coalesce(jsonb_agg(jsonb_build_object(
      'name',n.name,'active',coalesce(j.active,false),
      'status',case when m.completed_at>coalesce(r.end_time,'-infinity'::timestamptz) then m.status else coalesce(r.status,'not_run') end,
      'last_run',greatest(r.end_time,m.completed_at),
      'last_run_source',case when m.completed_at>coalesce(r.end_time,'-infinity'::timestamptz) then 'repair' else 'scheduled' end,
      'scheduled_status',coalesce(r.status,'not_run'),'scheduled_last_run',r.end_time,
      'repair_available',spec.schedule is not null,
      'configuration_needs_repair',spec.schedule is not null and (j.jobid is null or not j.active or j.schedule<>spec.schedule
        or btrim(regexp_replace(j.command,'[[:space:]]','','g'),';')<>btrim(regexp_replace(array_to_string(spec.commands,';'),'[[:space:]]','','g'),';'))
      ) order by n.name),'[]')
      from names n left join cron.job j on j.jobname=n.name
      left join lateral public._system_health_job_spec(n.name) spec on true
      left join lateral(select status,end_time from cron.job_run_details
        where jobid=j.jobid and status in ('succeeded','failed') order by start_time desc,runid desc limit 1) r on true
      left join lateral(select status,completed_at from public.system_health_repairs
        where job_name=n.name order by completed_at desc limit 1) m on true$q$ into jobs;
    execute $q$select exists(select 1 from cron.job j join cron.job_run_details r using(jobid)
      where j.jobname='dispatch-scheduled-notifications' and j.active and r.status='succeeded'
      and r.end_time>now()-interval '5 minutes')$q$ into dispatch_ok;
  end if;
  return result||jsonb_build_object('jobs',jobs,'dispatch_healthy',dispatch_ok,
    'repairs',coalesce((select jsonb_agg(to_jsonb(a)-'actor_id' order by completed_at desc)
      from (select * from public.system_health_repairs order by completed_at desc limit 10)a),'[]'::jsonb));
end $$;


commit;
