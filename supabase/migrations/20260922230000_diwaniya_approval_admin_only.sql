-- الديوانيات: الاعتماد للمالك والمدير فقط (جدول الصلاحيات)
-- كانت ديوانيات المراقب والمشرف تُعتمد تلقائياً. الأخبار تبقى: الإداريون
-- ينشرون أخبارهم مباشرة (canAutoPublishNews).

create or replace function public.trg_content_force_pending()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  caller_role text := coalesce(public.current_user_role(), 'anonymous');
  allowed boolean;
begin
  if auth.role() = 'service_role'
     or (auth.role() is null and session_user in ('postgres', 'supabase_admin', 'supabase_auth_admin')) then
    return new;
  end if;

  if caller_role in ('owner', 'admin') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    allowed := (tg_table_name = 'news' and caller_role in ('monitor', 'supervisor'))
      or (tg_table_name = 'news' and exists (
            select 1 from public.app_settings where news_requires_approval = false));
    if coalesce(new.approval_status, 'pending') <> 'pending' and not allowed then
      new.approval_status := 'pending';
      new.approved_by := null;
      if tg_table_name <> 'projects' then new.approved_at := null; end if;
    end if;
    return new;
  end if;

  -- UPDATE
  if new.approval_status is distinct from old.approval_status
     and new.approval_status <> 'pending' then
    raise exception 'approval_forbidden' using errcode = '42501',
      hint = 'الاعتماد للإدارة فقط';
  end if;
  return new;
end;
$$;
