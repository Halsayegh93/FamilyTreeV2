-- مُستخرَجة من سجل الإنتاج (supabase_migrations.schema_migrations)
-- كانت مطبَّقة على القاعدة لكن ملفها مفقود من المستودع.

-- أي إشعار مرتبط بطلب إداري يملأ «تخصّ» تلقائياً من الطلب،
-- فلا نحتاج تمريره يدوياً في كل نقطة إرسال.
create or replace function public.notifications_fill_subject()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if new.subject_member_id is null and new.request_id is not null then
    select coalesce(r.member_id, r.requester_id)
      into new.subject_member_id
      from public.admin_requests r
     where r.id = new.request_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notifications_fill_subject on public.notifications;
create trigger trg_notifications_fill_subject
  before insert on public.notifications
  for each row execute function public.notifications_fill_subject();;
