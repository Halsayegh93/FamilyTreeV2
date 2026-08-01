-- مُستخرَجة من سجل الإنتاج (supabase_migrations.schema_migrations)
-- كانت مطبَّقة على القاعدة لكن ملفها مفقود من المستودع.

-- «تخصّ»: العضو صاحب الحركة (لا مستلم الإشعار).
-- بعد التفريخ لكل عضو صار target_member_id = المستلم، فاحتجنا عموداً مستقلاً.
alter table public.notifications
  add column if not exists subject_member_id uuid references public.profiles(id) on delete set null;

create index if not exists notifications_subject_member_idx
  on public.notifications (subject_member_id);

-- التفريخ ينسخ العمود الجديد لكل النسخ الشخصية
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
    where coalesce(p.role, '') <> 'pending';
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

-- تعبئة رجعية للسجلات القديمة المرتبطة بطلب إداري
update public.notifications n
set subject_member_id = coalesce(r.member_id, r.requester_id)
from public.admin_requests r
where n.request_id = r.id
  and n.subject_member_id is null
  and coalesce(r.member_id, r.requester_id) is not null;;
