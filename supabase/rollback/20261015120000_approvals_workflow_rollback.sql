-- تراجع 20261015120000 (مسار الموافقات — طلب المالك ٢٠٢٦-١٠-١٥): يعيد الحي كما كان قبله حرفياً.
-- الطلبات المعلّقة وسط المسار ترجع طلبات معلّقة عادية (المسار القديم)؛ يضيع سجل الخطوات
-- وأعمدة التوصية/الاعتماد والمفتاح. لإيقاف المسار مؤقتاً يكفي إطفاء app_settings.approvals_workflow.
-- نسخة الآيفون التي تقرأ أعمدة المسار تحتاجها — لا تُرجع قبل إرجاع التطبيق أو إخفاء المسار فيه.

drop trigger if exists trg_zz_admin_request_workflow on public.admin_requests;
drop trigger if exists trg_zz_admin_request_submitted on public.admin_requests;
drop trigger if exists trg_zz_admin_request_stage on public.admin_requests;

drop function if exists public.advance_admin_request(uuid, text, text);
-- إن طُبّق 20261015150000 («طلب معلومات» منظّم) ولم يُرجع قبله: نسخته وأسماء حقوله
drop function if exists public.advance_admin_request(uuid, text, text, text[], jsonb);
drop function if exists public.approvals_info_field_label(text);
drop function if exists public.guard_admin_request_workflow();
drop function if exists public.log_admin_request_submitted();
drop function if exists public.set_admin_request_stage();
drop function if exists public.approvals_notify(uuid[], text, text, uuid, uuid, text, text, text);
drop function if exists public.admin_request_label(text);
drop function if exists public.workflow_specialist_ids(text);
drop function if exists public.is_workflow_specialist(text);
drop function if exists public.workflow_specialist_role(text);
drop function if exists public.approvals_workflow_on();

drop table if exists public.admin_request_steps;

alter table public.admin_requests
  drop constraint if exists admin_requests_stage_check,
  drop constraint if exists admin_requests_recommendation_check,
  drop constraint if exists admin_requests_info_fields_check,
  drop constraint if exists admin_requests_info_reply_check,
  drop column if exists stage,
  drop column if exists stage_since,
  drop column if exists recommendation,
  drop column if exists recommendation_note,
  drop column if exists recommended_by,
  drop column if exists recommended_at,
  drop column if exists info_request,
  drop column if exists approved_by,
  drop column if exists approved_at,
  drop column if exists approval_note,
  drop column if exists info_fields,
  drop column if exists info_reply;

alter table public.app_settings drop column if exists approvals_workflow;
