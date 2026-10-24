-- رسائل الدخول · «فك القفل» للمالك (طلب المالك ٢٠٢٦-١٠-٢٣ «حطه بالتطبيق»): يحذف قفل رقم وسجل طلباته فيقدر يطلب رمزاً فوراً.
-- القفل والسجل بالبصمة فقط (HMAC بمفتاح KWTSMS_HASH_KEY في الدوال الطرفية)، فالفك يمر بالدالة الطرفية kwtsms-admin
-- (إجراء «unlock» للمالك وحده) التي تحسب البصمة من الرقم وتستدعي هذه الدالة بمفتاح الخدمة.
-- التراجع: supabase/rollback/20261023120000_kwtsms_unlock_number_rollback.sql
create function public.kwtsms_unlock_number(p_phone_hash text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_locks int; v_requests int;
begin
  if p_phone_hash is null or p_phone_hash !~ '^[a-f0-9]{64}$' then
    raise exception 'Invalid phone hash' using errcode = '22023';
  end if;
  delete from public.kwtsms_number_locks where phone_hash = p_phone_hash;
  get diagnostics v_locks = row_count;
  delete from public.kwtsms_request_log where phone_hash = p_phone_hash;
  get diagnostics v_requests = row_count;
  return jsonb_build_object('was_locked', v_locks > 0, 'cleared_requests', v_requests);
end;
$$;
revoke all on function public.kwtsms_unlock_number(text) from public, anon, authenticated;
grant execute on function public.kwtsms_unlock_number(text) to service_role;
