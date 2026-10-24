-- تراجع 20261022110000_app_usage_sessions — يحذف جدول الجلسات والدوال. لا يمس app_usage_daily ولا app_usage_trend.
drop function if exists public.app_usage_engagement(int);
drop function if exists public.log_app_session(int, text);
drop table if exists public.app_usage_member_day;
