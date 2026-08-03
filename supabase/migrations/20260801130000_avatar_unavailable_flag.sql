-- تمييز «لا توجد صورة» عن «صورة ناقصة» — 2026-08-01
--
-- نفس منطق death_date_unknown: بعض الأعضاء لا توجد لهم صورة أصلاً (متوفّون قدامى،
-- أو رفضوا نشر صورهم). إبقاؤهم في تقارير «البيانات الناقصة» يجعل القائمة لا تنتهي.
--
-- إذا كان العلم true فالعضو مكتمل ولا يُحتسب ناقصاً.

begin;

alter table public.profiles
  add column if not exists avatar_unavailable boolean not null default false;

comment on column public.profiles.avatar_unavailable is
  'لا توجد صورة لهذا العضو — يُستثنى من تقارير البيانات الناقصة';

commit;
