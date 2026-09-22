begin;
-- The old join_requests table has no timestamp. Start retention now for legacy
-- rows rather than treating their unknown age as permission to delete them.
alter table public.join_requests add column if not exists created_at timestamptz not null default now();
do $$ begin
  if exists(select 1 from pg_extension where extname='pg_cron') then
    perform cron.schedule('cleanup-old-web-sessions','0 2 * * *',
      $job$delete from public.web_sessions where last_seen_at < now()-interval '30 days'$job$);
    perform cron.schedule('cleanup-old-join-requests','0 3 * * 3',
      $job$delete from public.join_requests where status in ('approved','rejected') and created_at < now()-interval '60 days'$job$);
  end if;
end $$;
commit;
