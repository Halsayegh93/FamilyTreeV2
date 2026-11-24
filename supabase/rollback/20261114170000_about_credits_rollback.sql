-- تراجع 20261114170000_about_credits: يحذف المفتاح وحارسه (التطبيق يرجع لاسم المالك وحده)
delete from public.app_config where key = 'about_credits';
drop trigger if exists trg_app_config_about_credits_guard on public.app_config;
drop function if exists private.app_config_about_credits_guard();
drop function if exists private.about_credits_problem(jsonb);
