-- تراجع: الإعلانات لمن له حساب دخول (نسخة 20261004150000) بدل «جهاز مسجّل فقط»

create or replace function public.fanout_broadcast_notification()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if new.target_member_id is not null then
    return new;
  end if;

  if coalesce(new.kind, '') in ('admin_broadcast', 'app_update') then
    insert into public.notifications
      (target_member_id, title, body, kind, created_by, created_at, is_read,
       request_id, request_type, details, subject_member_id)
    select p.id, new.title, new.body, new.kind, new.created_by,
           coalesce(new.created_at, timezone('utc', now())), false,
           new.request_id, new.request_type, new.details, new.subject_member_id
    from public.profiles p
    where coalesce(p.role, '') <> 'pending'
      -- فقط من دخل التطبيق (طلب المالك ٢٠٢٦-١٠-٠٤): من لم يدخل لا تتجمّع له نسخ
      -- إعلانات قديمة تظهر له أول ما يدخل — كانت كل إعلان يُنسخ ٢٧١٧ مرة لـ٤٥ مستخدماً
      and exists (select 1 from auth.users u
                  where u.id = p.id
                     or coalesce(u.raw_app_meta_data->>'profile_id', '') = p.id::text);
    return new;   -- الصف المشترك يبقى ليخرج الدفع مرة واحدة
  end if;

  insert into public.notifications
    (target_member_id, title, body, kind, created_by, created_at, is_read,
     request_id, request_type, details, subject_member_id)
  select p.id, new.title, new.body, new.kind, new.created_by,
         coalesce(new.created_at, timezone('utc', now())), false,
         new.request_id, new.request_type, new.details, new.subject_member_id
  from public.profiles p
  where p.role in ('owner', 'admin', 'monitor', 'supervisor');
  return null;
end;
$function$;
