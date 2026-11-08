-- «الرسائل» (رسائل الأعضاء الخاصة من «تواصل مع الإدارة»، request_type = 'contact_message') للمالك والمدير وحدهما
-- (مقترح «أدوار الإدارة» بموافقة المالك ٢٠٢٦-١١-٠٧، البند ٤، samples/admin-roles). في التطبيق: خانة
-- `inbox.messages` في app_config.admin_role_matrix (افتراضها للمراقب والمشرف "none").
-- APPLIED 2026-11-07 بموافقة المالك.
-- التراجع: supabase/rollback/20261107210000_contact_messages_owner_admin_rollback.sql
-- التجربة المحلية: cd supabase/tests/family_links && node admin_role_matrix.test.mjs (القسم الأخير)
--
-- قبل: can_handle_admin_request يسمح للمراقب بكل شي ما عدا البلاغات (ومنها contact_message)، وللمشرف البلاغات
--      + contact_message؛ وسياسة القراءة تعرض كل الطلبات للأدوار الإدارية الأربعة.
-- بعد: contact_message للمالك والمدير فقط — لا تعديل/معالجة (سياسة التحديث، decide_admin_request) ولا قراءة للمراقب
--      والمشرف. صاحب الرسالة يقرأ رسالته كما كان. بقية الأنواع كما هي حرفياً (ومنها lineage_request للمراقب).

create or replace function public.can_handle_admin_request(p_type text)
returns boolean
language sql
stable security definer
set search_path to 'public'
as $function$
  select case public.current_user_role()
    when 'owner' then true
    when 'admin' then true
    when 'monitor' then coalesce(p_type, '') not in ('news_report', 'content_report', 'contact_message')
    when 'supervisor' then coalesce(p_type, '') in ('news_report', 'content_report')
    else false
  end;
$function$;

drop policy if exists admin_requests_select_moderator_or_owner on public.admin_requests;
create policy admin_requests_select_moderator_or_owner on public.admin_requests
  for select
  using (
    (requester_id = auth.uid())
    or (member_id = auth.uid())
    or (public.current_user_role() = any (array['admin'::text, 'owner'::text]))
    or (public.current_user_role() = any (array['supervisor'::text, 'monitor'::text])
        and request_type is distinct from 'contact_message')
  );
