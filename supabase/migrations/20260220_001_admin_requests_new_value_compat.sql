-- Compatibility patch: ensure admin_requests.new_value exists
alter table if exists public.admin_requests
  add column if not exists new_value text;
