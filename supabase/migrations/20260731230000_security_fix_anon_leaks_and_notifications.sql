-- إصلاح أمني — 2026-07-31
-- ١. إغلاق تسريب diwaniyas و projects للزوار غير المسجّلين (مؤكَّد تجريبياً)
-- ٢. منع العضو العادي من إنشاء إشعارات بثّ للعائلة كلها (وإطلاق Push)
-- ٣. منع العضو العادي من تعديل إشعارات البثّ الإدارية
--
-- ملاحظة منهجية: الإنتاج يحتوي سياسات غير مسجّلة في المستودع (ظهر ذلك في projects
-- التي كانت مقروءة للزوار رغم أن الـmigration يشترط auth). لذلك نحذف ديناميكياً
-- كل سياسات SELECT القائمة على الجدولين قبل إنشاء البديل الآمن.

begin;

-- ═══════════════════════════════════════════════════════════════
-- ١) diwaniyas — القراءة للمسجّلين فقط
-- ═══════════════════════════════════════════════════════════════
do $$
declare p record;
begin
  for p in
    select policyname from pg_policies
    where schemaname = 'public' and tablename = 'diwaniyas' and cmd in ('SELECT', 'ALL')
  loop
    execute format('drop policy if exists %I on public.diwaniyas', p.policyname);
  end loop;
end $$;

create policy "diwaniyas_select_authenticated" on public.diwaniyas
for select
to authenticated
using (
  auth.uid() is not null
  and (
    approval_status = 'approved'
    or owner_id = auth.uid()
    or public.current_user_role() in ('supervisor', 'monitor', 'admin', 'owner')
  )
);

-- ═══════════════════════════════════════════════════════════════
-- ٢) projects — القراءة للمسجّلين فقط، والمخفي/المرفوض للإدارة فقط
-- ═══════════════════════════════════════════════════════════════
do $$
declare p record;
begin
  for p in
    select policyname from pg_policies
    where schemaname = 'public' and tablename = 'projects' and cmd in ('SELECT', 'ALL')
  loop
    execute format('drop policy if exists %I on public.projects', p.policyname);
  end loop;
end $$;

create policy "projects_select_authenticated" on public.projects
for select
to authenticated
using (
  auth.uid() is not null
  and (
    public.current_user_role() in ('owner', 'admin', 'monitor', 'supervisor')
    or owner_id = auth.uid()
    or (is_hidden = false and approval_status = 'approved')
  )
);

-- ═══════════════════════════════════════════════════════════════
-- ٣) notifications — إغلاق سياسة الإدراج المفتوحة
--    كانت notifications_insert_authenticated (auth.uid() is not null) باقية
--    بالتوازي مع سياسة المشرفين، والسياسات تُجمع بـOR ⇒ أي عضو يبثّ للجميع.
--    البديل: المشرفون بلا قيد، والعضو العادي لنفسه أو لذريّته فقط، وبلا بثّ.
-- ═══════════════════════════════════════════════════════════════
drop policy if exists "notifications_insert_authenticated" on public.notifications;
drop policy if exists "notifications_insert_moderator" on public.notifications;

create policy "notifications_insert_moderator_or_self_scope" on public.notifications
for insert
to authenticated
with check (
  public.current_user_role() in ('supervisor', 'monitor', 'admin', 'owner')
  or (
    -- العضو العادي: إشعار موجَّه فقط (لا بثّ)، ولنفسه أو لأحد ذريّته
    target_member_id is not null
    and (
      target_member_id = auth.uid()
      or public.is_descendant_of_caller(target_member_id)
    )
  )
);

-- تعديل الإشعارات: إسقاط شرط target_member_id is null الذي فتح إشعارات البثّ للجميع
drop policy if exists "notifications_update_own" on public.notifications;

create policy "notifications_update_own_or_moderator" on public.notifications
for update
to authenticated
using (
  target_member_id = auth.uid()
  or public.current_user_role() in ('supervisor', 'monitor', 'admin', 'owner')
)
with check (
  target_member_id = auth.uid()
  or public.current_user_role() in ('supervisor', 'monitor', 'admin', 'owner')
);

commit;

-- ═══════════════════════════════════════════════════════════════
-- التحقّق بعد التطبيق
-- ═══════════════════════════════════════════════════════════════
-- select tablename, policyname, cmd, roles, qual, with_check
-- from pg_policies
-- where schemaname = 'public' and tablename in ('diwaniyas','projects','notifications')
-- order by tablename, cmd, policyname;
--
-- ثم من الطرفية (يجب أن ترجع [] فارغة):
--   curl -s "$SUPABASE_URL/rest/v1/diwaniyas?select=id&limit=1" \
--        -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY"
--   curl -s "$SUPABASE_URL/rest/v1/projects?select=id&limit=1" \
--        -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY"
