-- المزامنة الفورية بين الأجهزة: النشر كان يضمّ notifications و profiles فقط،
-- فتغييرات شجرة النساء/الأخبار/المشاريع لا تصل الأجهزة الأخرى إلا بإعادة جلب يدوية.
-- RLS يبقى مطبَّقاً على أحداث realtime كما على الاستعلامات — لا كشف جديد.
do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and tablename = 'women_members') then
    alter publication supabase_realtime add table public.women_members;
  end if;
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and tablename = 'news') then
    alter publication supabase_realtime add table public.news;
  end if;
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and tablename = 'projects') then
    alter publication supabase_realtime add table public.projects;
  end if;
end $$;

select tablename from pg_publication_tables where pubname = 'supabase_realtime' order by 1;
