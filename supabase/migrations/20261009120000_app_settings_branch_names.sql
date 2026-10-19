-- أسماء الفروع المخصّصة (طلب المالك ٢٠٢٦-١٠-٠٩): «اختر فرعاً» في بحث الشجرة يعرض اسماً يختاره المالك
-- لكل فرع (مثلاً «فرع موسى» ← «آل موسى»). خريطة: معرّف رأس الفرع (uuid نصّاً) ← الاسم.
-- إضافة فقط: القراءة لكل مستخدم مسجّل والتعديل للمالك وحده — سياسات app_settings الحالية كما هي.
alter table public.app_settings
  add column if not exists branch_names jsonb not null default '{}'::jsonb;

comment on column public.app_settings.branch_names is
  'أسماء الفروع المخصّصة: {"<profile uuid>": "الاسم"} — يعدّلها المالك من إعدادات التطبيق';
