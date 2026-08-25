-- فصل «نطاق الظهور» عن «الإخفاء» — كانا عموداً واحداً بمعنيين متناقضين.
--
-- المشكلة: الموقع والتطبيق يكتبان كلاهما في is_hidden_from_tree، لكن بدلالتين:
--   الموقع  → true تعني «موجودة في الموقع فقط»
--   التطبيق → true تعني «مخفية من الشجرة»
-- فضبط أحدهما يقلب الآخر، وثلاث حالات مطلوبة لا يحملها عمود ثنائي.
--
-- الحلّ: عمود مستقلّ للنطاق. القيمة الافتراضية false تُبقي كل صفّ قائم على
-- معنى «مخفي» — وهو التفسير الآمن، إذ يبقى ظاهراً لصاحبه في «عائلتي».
--
-- الحالات الثلاث بعد هذا:
--   is_web_only = true                          → الموقع فقط (التطبيق يتجاهلها)
--   is_web_only = false · is_hidden = false     → الشجرة و«عائلتي»
--   is_web_only = false · is_hidden = true      → «عائلتي» فقط، لا الشجرة
alter table public.women_members
  add column if not exists is_web_only boolean not null default false;

comment on column public.women_members.is_web_only is
  'سجلّ الموقع فقط — التطبيقان يتجاهلانه كلياً (لا شجرة ولا عائلتي).';

create index if not exists women_members_web_only_idx
  on public.women_members (is_web_only) where is_web_only;
