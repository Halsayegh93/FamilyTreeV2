-- تراجع 20261107210000_contact_messages_owner_admin: يعيد الحي حرفياً (pg_get_functiondef / pg_policies ٢٠٢٦-١١-٠٧).
create or replace function public.can_handle_admin_request(p_type text)
returns boolean
language sql
stable security definer
set search_path to 'public'
as $function$
  select case public.current_user_role()
    when 'owner' then true
    when 'admin' then true
    when 'monitor' then coalesce(p_type, '') not in ('news_report', 'content_report')
    when 'supervisor' then coalesce(p_type, '') in ('news_report', 'content_report', 'contact_message')
    else false
  end;
$function$;

drop policy if exists admin_requests_select_moderator_or_owner on public.admin_requests;
create policy admin_requests_select_moderator_or_owner on public.admin_requests
  for select
  using ((requester_id = auth.uid()) or (member_id = auth.uid())
    or (public.current_user_role() = any (array['supervisor'::text, 'monitor'::text, 'admin'::text, 'owner'::text])));
