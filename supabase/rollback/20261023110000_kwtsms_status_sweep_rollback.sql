-- تراجع 20261023110000_kwtsms_status_sweep — يلغي المهمة والدالتين. الحالات المحفوظة تبقى (عمود موجود من قبل).
-- الدالة الطرفية kwtsms-cron (النسخة مع status_sweep) تبقى سليمة: ترد 503 لو استُدعيت بلا الدالة.
select cron.unschedule('kwtsms-status-sweep') where exists (select 1 from cron.job where jobname = 'kwtsms-status-sweep');
drop function if exists public.kwtsms_status_sweep_job();
drop function if exists public.kwtsms_pending_status_checks(int);
