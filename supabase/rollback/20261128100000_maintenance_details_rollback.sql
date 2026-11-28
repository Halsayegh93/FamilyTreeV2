-- تراجع 20261128100000_maintenance_details: يحذف سبب الصيانة (النسخ التي تقرؤه تعود للنص الافتراضي).
alter table public.app_settings drop constraint if exists app_settings_maintenance_message_len;
alter table public.app_settings drop column if exists maintenance_message;
