-- تراجع 20261021100000_death_alert_days — التطبيقات ترجع لقيمتها المدمجة (٧ أيام) إن لم تجد العمود.
alter table public.app_settings drop column if exists death_alert_days;
