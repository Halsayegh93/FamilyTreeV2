-- تراجع 20261021080000_owner_login_code («اعرض الرمز» للمالك) — يمسح كل الرموز المحفوظة وسجل العرض.
-- الدالة الطرفية send-sms-kwtsms (النسخة التي تستدعي store_login_code) تبقى سليمة بعده: النداء يرجع 404 ويُبلع
-- (بأفضل جهد، لا يمس الإرسال)؛ ولإرجاعها حرفياً: انشر نسخة الدالة السابقة بـ --no-verify-jwt.
select cron.unschedule('login-codes-cleanup') where exists (select 1 from cron.job where jobname = 'login-codes-cleanup');
drop function if exists public.cleanup_login_codes();
drop function if exists public.owner_reveal_login_code(text);
drop function if exists public.owner_login_codes(int);
drop function if exists public.store_login_code(text, text);
drop function if exists private.login_code_valid(text, timestamptz, timestamptz);
drop table if exists private.login_code_views;
drop table if exists private.login_codes;
