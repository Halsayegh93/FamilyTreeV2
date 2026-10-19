-- تراجع 20261009120000: حذف عمود أسماء الفروع (تضيع الأسماء المحفوظة)
alter table public.app_settings drop column if exists branch_names;
