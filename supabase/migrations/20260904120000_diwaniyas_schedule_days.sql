-- أيام انعقاد الديوانية كبيانات مهيكلة (بدل النص الحر فقط)
-- 0 = السبت، 1 = الأحد، 2 = الإثنين، 3 = الثلاثاء، 4 = الأربعاء، 5 = الخميس، 6 = الجمعة
-- (نفس ترقيم أيام الأسبوع المستخدم في نموذج إضافة الديوانية في التطبيق)
--
-- يُستخدم لشريحة «ديوانية اليوم / هذا الأسبوع» في الرئيسية.
-- schedule_text يبقى كما هو للعرض النصي.

alter table public.diwaniyas
    add column if not exists schedule_days smallint[] not null default '{}';

comment on column public.diwaniyas.schedule_days is
    'أيام الانعقاد الأسبوعية: 0=السبت … 6=الجمعة. يُملأ من نموذج الإضافة/التعديل في التطبيق.';

-- تعبئة أولية من النص الحر للصفوف القديمة (أفضل جهد — الأسماء العربية والإنجليزية)
update public.diwaniyas d
set schedule_days = coalesce(
    (
        select array_agg(x.day order by x.day)
        from (
            select 0 as day where d.schedule_text ilike '%السبت%'   or d.schedule_text ilike '%Saturday%'
            union select 1 where d.schedule_text ilike '%الأحد%'    or d.schedule_text ilike '%Sunday%'
            union select 2 where d.schedule_text ilike '%الإثنين%'  or d.schedule_text ilike '%الاثنين%' or d.schedule_text ilike '%Monday%'
            union select 3 where d.schedule_text ilike '%الثلاثاء%' or d.schedule_text ilike '%Tuesday%'
            union select 4 where d.schedule_text ilike '%الأربعاء%' or d.schedule_text ilike '%Wednesday%'
            union select 5 where d.schedule_text ilike '%الخميس%'   or d.schedule_text ilike '%Thursday%'
            union select 6 where d.schedule_text ilike '%الجمعة%'   or d.schedule_text ilike '%Friday%'
        ) x
    ),
    '{}'
)
where d.schedule_text is not null
  and (d.schedule_days is null or cardinality(d.schedule_days) = 0);

-- «كل يوم»
update public.diwaniyas
set schedule_days = '{0,1,2,3,4,5,6}'
where (schedule_text ilike '%كل يوم%' or schedule_text ilike '%Every day%')
  and cardinality(schedule_days) = 0;
