-- ثغرات متوسطة من فحص السيرفر (2026-09-22) — مطابقة السيرفر لجدول الصلاحيات
--
-- ١) المسؤول المجمّد كان يحتفظ بصلاحياته: is_moderator تتجاهل الحالة.
--    صارت تعتمد current_user_role (المجمّد = 'frozen').
-- ٢) الديوانيات والمشاريع: التعديل والحذف لصاحبها أو المالك/المدير فقط
--    (كان المراقب والمشرف يحذفون). الاعتماد محمي أصلاً بـ trg_content_force_pending.
-- ٣) رموز الأجهزة: القراءة والحذف لصاحب الجهاز أو المالك/المدير فقط.
-- ٤) طلبات الإدارة: كل دور يعالج مجاله — المراقب طلبات الشجرة والأعضاء،
--    المشرف البلاغات، المالك/المدير الكل. الرسائل (contact_message) للجميع.
-- ٥) صور الأعضاء غير المعتمدة كانت تظهر للكل (سياسة قراءة مفتوحة تتغلّب).
-- ٦) حذف الأخبار: المالك كان ناقصاً من السياسة.

-- ١
create or replace function public.is_moderator()
returns boolean
language sql
stable security definer
set search_path to 'public'
as $$
  select coalesce(public.current_user_role() in ('owner', 'admin', 'monitor', 'supervisor'), false);
$$;

-- ٢ الديوانيات
drop policy if exists diwaniyas_delete on public.diwaniyas;
drop policy if exists diwaniya_delete_owner_or_moderator on public.diwaniyas;
drop policy if exists diwaniyas_update on public.diwaniyas;
drop policy if exists diwaniya_update_moderator on public.diwaniyas;
create policy diwaniyas_delete on public.diwaniyas for delete to authenticated
  using (owner_id = auth.uid() or public.current_user_role() in ('owner', 'admin'));
create policy diwaniyas_update_admin on public.diwaniyas for update to authenticated
  using (public.current_user_role() in ('owner', 'admin'))
  with check (public.current_user_role() in ('owner', 'admin'));
-- (diwaniya_update_owner يبقى: صاحب الديوانية يعدّلها)

-- ٢ المشاريع
drop policy if exists projects_delete on public.projects;
drop policy if exists projects_delete_owner_or_mod on public.projects;
drop policy if exists projects_update on public.projects;
drop policy if exists projects_update_owner_or_mod on public.projects;
create policy projects_delete on public.projects for delete to authenticated
  using (owner_id = auth.uid() or public.current_user_role() in ('owner', 'admin'));
create policy projects_update on public.projects for update to authenticated
  using (owner_id = auth.uid() or public.current_user_role() in ('owner', 'admin'))
  with check (owner_id = auth.uid() or public.current_user_role() in ('owner', 'admin'));

-- ٣ رموز الأجهزة
drop policy if exists device_tokens_select_self_or_moderator on public.device_tokens;
drop policy if exists device_tokens_delete_moderator on public.device_tokens;
create policy device_tokens_select_self_or_admin on public.device_tokens for select to authenticated
  using (member_id = auth.uid() or public.current_user_role() in ('owner', 'admin'));
-- (device_tokens_admin_delete + device_tokens_delete_self يبقيان)

-- ٤ طلبات الإدارة حسب المجال
create or replace function public.can_handle_admin_request(p_type text)
returns boolean
language sql
stable security definer
set search_path to 'public'
as $$
  select case public.current_user_role()
    when 'owner' then true
    when 'admin' then true
    when 'monitor' then coalesce(p_type, '') not in ('news_report', 'content_report')
    when 'supervisor' then coalesce(p_type, '') in ('news_report', 'content_report', 'contact_message')
    else false
  end;
$$;

drop policy if exists admin_requests_update_moderator on public.admin_requests;
drop policy if exists admin_requests_delete_moderator on public.admin_requests;
create policy admin_requests_update_by_scope on public.admin_requests for update to authenticated
  using (public.can_handle_admin_request(request_type))
  with check (public.can_handle_admin_request(request_type));
create policy admin_requests_delete_by_scope on public.admin_requests for delete to authenticated
  using (public.can_handle_admin_request(request_type));

-- ٥ صور الأعضاء: تبقى gallery_select وحدها (معتمدة، أو صاحبها، أو الإدارة)
drop policy if exists member_gallery_select_authenticated on public.member_gallery_photos;

-- ٦ حذف الأخبار
drop policy if exists news_delete_owner_or_moderator on public.news;
create policy news_delete_owner_or_moderator on public.news for delete to authenticated
  using (author_id = auth.uid() or posted_by = auth.uid()
         or public.current_user_role() in ('owner', 'admin', 'supervisor'));
