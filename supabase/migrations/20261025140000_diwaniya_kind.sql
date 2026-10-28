-- نوع المجلس: ديوانية أو حسينية (اختيار «حسينية» في التطبيق لم يكن يُحفظ — لا عمود). موافقة المالك ٢٠٢٦-١٠-٢٥ «سو من ١ الى ٥».
-- التطبيق يكتبه بعد الإضافة (`DiwaniyasViewModel.addDiwaniya` ← update kind) ويقرؤه مع «select *»؛ القديمة = ديوانية.
-- التراجع: supabase/rollback/20261025140000_diwaniya_kind_rollback.sql
alter table public.diwaniyas
  add column if not exists kind text not null default 'diwaniya'
  constraint diwaniyas_kind_check check (kind in ('diwaniya', 'husseiniya'));
