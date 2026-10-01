-- نوع المجلس: ديوانية أو حسينية (طلب المالك ٢٠٢٦-٠٩-٢٦)
-- عمود جديد بقيمة افتراضية 'diwaniya' — كل الموجود يبقى ديوانية، والنسخ
-- القديمة من التطبيق لا تتأثر (لا تقرأ العمود ولا تكتبه).
alter table public.diwaniyas
  add column if not exists kind text not null default 'diwaniya';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'diwaniyas_kind_check') then
    alter table public.diwaniyas
      add constraint diwaniyas_kind_check check (kind in ('diwaniya', 'husseiniya'));
  end if;
end $$;
