-- تراجع 20261111150000_admin_request_sent_info — يرجع جدول admin_requests كما كان قبله.
-- يحذف العمودين sent_from / sent_via بما سُجّل فيهما، وسجلّ admin_request_events بما فيه (لا رجعة لتلك البيانات)،
-- والمشغّلات الثلاثة ودوالها.
-- ما ملأه المشغّل في replied_by / replied_at أثناء عمله يبقى (بيانات صحيحة عن من أغلق الطلب).
-- التطبيقات بعده: الإدراج بالعمود الغائب يُعاد بلا sent_from (مسار احتياطي في الآيفون)، والعرض يرجع للمسار المستنتج.
drop trigger if exists trg_zzz_profiles_activation_event on public.profiles;
drop function if exists public.trg_profiles_activation_event();
drop trigger if exists trg_zzz_admin_request_events on public.admin_requests;
drop function if exists public.trg_admin_request_events();
drop function if exists public.admin_request_log_event(uuid, text, uuid, text, text);
drop table if exists public.admin_request_events;
drop trigger if exists trg_zzz_admin_request_sent_info on public.admin_requests;
drop function if exists public.trg_admin_request_sent_info();
alter table public.admin_requests
  drop column if exists sent_from,
  drop column if exists sent_via;
