-- تراجع 20261029150000_account_delete_hardening
select cron.unschedule('account-delete-deadline') where exists (select 1 from cron.job where jobname = 'account-delete-deadline');
drop function if exists public.account_delete_deadline_tick();
delete from public.app_config where key in ('account_deleted_sms', 'account_delete_escalate_days');
-- الدالة الطرفية delete-account: أعد نشر النسخة v54 (supabase/functions/delete-account قبل هذا التعديل في git، verify_jwt=true).
