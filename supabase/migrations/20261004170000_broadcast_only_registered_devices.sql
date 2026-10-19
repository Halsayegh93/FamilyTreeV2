-- إعلانات «للجميع» لمن له جهاز مسجّل فقط (معيار أشد — طلب المالك ٢٠٢٦-١٠-٠٤)
--
-- بعد 20261004150000 (نسخ لمن له حساب دخول — ٤٣) طلب المالك معياراً أشد: «جهاز مسجّل فقط»
-- (٣٢ عضواً). العضو الذي يدخل لاحقاً ويسجّل جهازه تبدأ إعلاناته الجديدة من حينها.
-- لا يتغيّر شيء آخر: الدفع نفسه كان وما زال لكل الأجهزة المسجّلة، والربط يحذف القديم.
-- التراجع: supabase/rollback/20261004170000_broadcast_only_registered_devices_rollback.sql

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
      -- فقط من له جهاز مسجّل (معيار أشد — طلب المالك ٢٠٢٦-١٠-٠٤): الإعلان يصل نسخةً
      -- لمن يصله دفعه أصلاً؛ من لم يدخل أو دخل بلا جهاز لا تتجمّع له نسخ قديمة
      and exists (select 1 from public.device_tokens d where d.member_id = p.id);
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
