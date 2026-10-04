-- حالة الحساب في سياسات شجرة النساء، والمشرف يقرأ فقط، ولا إشعار باسم غيرك (فحص الثغرات ٢٠٢٦-١٠-٠٤، أ-١٣)
--
-- women_members_write و external_spouses_*: كانت تفحص profiles.role وحده، فمن جُمّد وهو مدير أو
--   مراقب يبقى يكتب في الشجرة. الآن current_user_role() (المجمّد = 'frozen'). المشرف يقرأ
--   external_spouses ولا يكتب — طلب المالك «المشرف يشوف بلا تعديل»، ولا يكتب فيه أي تطبيق إلا
--   «إدارة الصلات» في الموقع وهي للمالك والمدير والمراقب.
-- guard_notification_sender: لغير الإدارة، مرسل الإشعار (created_by) هو المتصل دائماً، ولا
--   إعلان عام (admin_broadcast / app_update) ولو لشخص واحد. التطبيقات ودوال السيرفر تضع المتصل
--   مرسلاً أصلاً؛ هذا يمنع من يكتب مباشرة أن يظهر إشعاره لأبنائه أو للإدارة «من المالك». يعمل قبل
--   مشغّلات الإشعارات الأخرى (الاسم يُرتَّب أولاً) فالتوزيع ينسخ المرسل الصحيح.
-- التراجع: supabase/rollback/20261004220000_staff_status_and_notification_sender_rollback.sql
-- التجربة: supabase/tests/family_links/staff_status_and_sender.test.mjs

alter policy women_members_write on public.women_members
  using (public.current_user_role() = any (array['owner','admin','monitor']))
  with check (public.current_user_role() = any (array['owner','admin','monitor']));

alter policy external_spouses_select_mods on public.external_spouses
  using (public.current_user_role() = any (array['owner','admin','monitor','supervisor']));

alter policy external_spouses_write_mods on public.external_spouses
  using (public.current_user_role() = any (array['owner','admin','monitor']))
  with check (public.current_user_role() = any (array['owner','admin','monitor']));

create or replace function public.guard_notification_sender()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  me uuid := public.current_profile_id();
begin
  -- السيرفر وصيانة SQL والمهام المجدولة
  if auth.role() = 'service_role'
     or (auth.role() is null and session_user in ('postgres','supabase_admin','supabase_auth_admin')) then
    return new;
  end if;
  -- بلا دخول: سياسات الجدول ترفضه
  if me is null then
    return new;
  end if;
  if coalesce(public.current_user_role(), 'pending') in ('owner','admin','monitor','supervisor') then
    return new;
  end if;
  if coalesce(new.kind, '') in ('admin_broadcast','app_update') then
    raise exception 'notification_kind_not_allowed' using errcode = '42501';
  end if;
  new.created_by := case when exists (select 1 from public.profiles p where p.id = me) then me end;
  return new;
end;
$function$;

revoke all on function public.guard_notification_sender() from public, anon, authenticated;

drop trigger if exists trg_a_guard_notification_sender on public.notifications;
create trigger trg_a_guard_notification_sender
  before insert on public.notifications
  for each row execute function public.guard_notification_sender();
