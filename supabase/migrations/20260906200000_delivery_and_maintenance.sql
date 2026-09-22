begin;
create table if not exists public.delivery_attempts (
  scope text not null, actor text not null, dedupe_key text not null,
  attempted_at timestamptz not null default now()
);
create index if not exists delivery_attempts_lookup on public.delivery_attempts(scope,actor,attempted_at desc);
alter table public.delivery_attempts enable row level security;
revoke all on public.delivery_attempts from public,anon,authenticated;
grant all on public.delivery_attempts to service_role;

create or replace function public.reserve_delivery_attempt(p_scope text,p_actor text,p_key text,p_limit int default 10,p_dedupe_seconds int default 300)
returns text language plpgsql security definer set search_path=public as $$
begin
  if auth.role() is distinct from 'service_role' then raise exception 'service_only' using errcode='42501'; end if;
  if p_scope is null or p_actor is null or p_key is null or p_limit not between 1 and 100 or p_dedupe_seconds not between 1 and 604800 then raise exception 'invalid_limits'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_scope||':'||p_actor,0));
  if exists(select 1 from delivery_attempts where scope=p_scope and actor=p_actor and dedupe_key=p_key and attempted_at>now()-make_interval(secs=>p_dedupe_seconds)) then return 'duplicate'; end if;
  if (select count(*) from delivery_attempts where scope=p_scope and actor=p_actor and attempted_at>now()-interval '1 hour') >= p_limit then return 'rate_limited'; end if;
  insert into delivery_attempts(scope,actor,dedupe_key) values(p_scope,p_actor,p_key);
  return 'allowed';
end; $$;
revoke all on function public.reserve_delivery_attempt(text,text,text,int,int) from public,anon,authenticated;
grant execute on function public.reserve_delivery_attempt(text,text,text,int,int) to service_role;

create table if not exists public.weekly_digest_runs(week_start date primary key, notified int not null, completed_at timestamptz not null default now());
alter table public.weekly_digest_runs enable row level security;
revoke all on public.weekly_digest_runs from public,anon,authenticated;
grant all on public.weekly_digest_runs to service_role;
create or replace function public.publish_weekly_digest(p_title text,p_body text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare week date := date_trunc('week',now() at time zone 'Asia/Kuwait')::date; total int;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'service_only' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended('weekly_digest:'||week::text,0));
  if exists(select 1 from weekly_digest_runs where week_start=week) then return jsonb_build_object('duplicate',true,'notified',0); end if;
  insert into notifications(target_member_id,title,body,kind,is_read)
    select id,left(p_title,200),left(p_body,4000),'weekly_digest',false from profiles where status='active';
  get diagnostics total = row_count;
  insert into weekly_digest_runs(week_start,notified) values(week,total);
  return jsonb_build_object('duplicate',false,'notified',total);
end; $$;
revoke all on function public.publish_weekly_digest(text,text) from public,anon,authenticated;
grant execute on function public.publish_weekly_digest(text,text) to service_role;

create or replace function public.owns_story_storage_file(p_name text,p_member uuid)
returns boolean language plpgsql security definer set search_path=public as $$
begin
  if auth.role() is distinct from 'service_role' then raise exception 'service_only' using errcode='42501'; end if;
  return exists(select 1 from storage.objects o where o.bucket_id='stories' and o.name=p_name
    and (coalesce(to_jsonb(o)->>'owner_id',to_jsonb(o)->>'owner')=p_member::text
      or exists(select 1 from auth.users u where u.id::text=coalesce(to_jsonb(o)->>'owner_id',to_jsonb(o)->>'owner')
        and u.raw_app_meta_data->>'profile_id'=p_member::text)));
end; $$;
revoke all on function public.owns_story_storage_file(text,uuid) from public,anon,authenticated;
grant execute on function public.owns_story_storage_file(text,uuid) to service_role;

-- Internal SQL jobs have no public HTTP endpoint and don't send notifications.
do $$ begin
  if exists(select 1 from pg_extension where extname='pg_cron') then
    perform cron.schedule('cleanup-delivery-attempts','15 3 * * *', $job$delete from public.delivery_attempts where attempted_at < now()-interval '8 days'$job$);
  end if;
end $$;
commit;
