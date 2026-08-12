-- ترتيب أبناء البنات: الجدول لم يكن فيه أي عمود ترتيب، فكان ما يرجع من
-- القاعدة اعتباطياً ولا يمكن إعادة ترتيبه — بخلاف الأبناء الذكور في
-- profiles.sort_order الذي يقرأه التطبيق والموقع معاً.
--
-- إضافة بحتة: عمود بقيمة افتراضية، فلا تتأثر صفوف قائمة، وتطبيق الآيفون
-- يتجاهل الأعمدة التي لا يعرفها.
alter table public.web_relatives
  add column if not exists sort_order integer not null default 0;

-- الفرز يقع دائماً ضمن أبناء أمٍّ واحدة، والفهرس يغطّي المسارين
-- (بنت من التطبيق: parent_woman_id · بنت من الموقع: parent_rel_id).
create index if not exists web_relatives_parent_order_idx
  on public.web_relatives (parent_woman_id, parent_rel_id, sort_order);
