-- تراجع 20261020180000: الحد الأدنى للانتظار يرجع ٦٠ ثانية (يرفع أي قيمة أقل إلى ٦٠ قبل إعادة القيد)
update public.app_settings set sms_wait_seconds = 60 where sms_wait_seconds < 60;
alter table public.app_settings drop constraint app_settings_sms_wait_seconds_check;
alter table public.app_settings add constraint app_settings_sms_wait_seconds_check
  check (sms_wait_seconds between 60 and 600);
