-- تراجع 20261125130000_post_approval_review — يرجع admin_requests وapp_settings كما كانا قبله.
-- يحذف أعمدة المراجعة الأربعة بما سُجّل فيها (لا رجعة لتلك البيانات) والمفتاح approvals_post_review،
-- والمشغّل ودالته ودالة review_admin_request.
-- ما ملأه المشغّل في replied_by / replied_at يبقى (بيانات صحيحة عن من وافق ومتى)، وإشعارات «post_review»
-- المرسلة تبقى في صناديق أصحابها، وأحداث reviewed_* في admin_request_events (إن وُجد) تبقى سجلّاً.
-- التطبيقات بعده: الآيفون يقرأ الأعمدة بتسامح (غائبة = لا مراجعة) ويخفي مفتاح الإعداد.
drop trigger if exists trg_zzz_admin_request_post_review on public.admin_requests;
drop function if exists public.trg_admin_request_post_review();
drop function if exists public.review_admin_request(uuid, text, text);
drop function if exists public.post_review_on();
drop index if exists public.admin_requests_review_pending_idx;
alter table public.admin_requests
  drop constraint if exists admin_requests_review_status_check;
alter table public.admin_requests
  drop column if exists review_status,
  drop column if exists reviewed_by,
  drop column if exists reviewed_at,
  drop column if exists review_note;
alter table public.app_settings
  drop column if exists approvals_post_review;
