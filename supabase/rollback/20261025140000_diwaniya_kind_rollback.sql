-- تراجع 20261025140000_diwaniya_kind — التطبيق يتجاهل غياب العمود (يُعامل كل المجالس ديوانيات)
alter table public.diwaniyas drop column if exists kind;
