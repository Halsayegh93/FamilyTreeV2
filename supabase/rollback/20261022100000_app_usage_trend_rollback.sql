-- تراجع 20261022100000_app_usage_trend — يحذف اللقطات اليومية ويلغي المهمة. لا يمس app_usage_stats الحالية.
select cron.unschedule('app-usage-daily') where exists (select 1 from cron.job where jobname = 'app-usage-daily');
drop function if exists public.app_usage_trend(int);
drop function if exists public.record_app_usage_day();
drop function if exists public.app_usage_member_total();
drop function if exists public.app_usage_count_since(timestamptz);
drop table if exists public.app_usage_daily;
