-- تمييز «تاريخ وفاة غير معروف» عن «تاريخ ناقص» — 2026-08-01
--
-- المشكلة: عمود death_date من نوع date، فلا يمكن تخزين «غير معروف» فيه.
-- والنتيجة أن المتوفّين الذين لا يُعرف تاريخ وفاتهم يظهرون أبداً في قائمة
-- «بيانات ناقصة» رغم أنه لا يوجد ما يُستكمل.
--
-- الحل: علم منطقي مستقل. إذا كان true فالعضو مكتمل البيانات ولا يُحتسب ناقصاً.

begin;

alter table public.profiles
  add column if not exists death_date_unknown boolean not null default false;

comment on column public.profiles.death_date_unknown is
  'تاريخ الوفاة غير معروف — يُستثنى من تقارير البيانات الناقصة';

commit;
