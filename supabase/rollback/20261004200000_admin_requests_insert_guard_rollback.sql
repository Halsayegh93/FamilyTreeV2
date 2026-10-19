-- تراجع: إزالة حارس إدراج طلبات المراجعة (يرجع الجدول بلا مشغّلات كما كان)
drop trigger if exists trg_guard_admin_request_insert on public.admin_requests;
drop function if exists public.guard_admin_request_insert();
