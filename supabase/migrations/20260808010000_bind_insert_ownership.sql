-- تضييق سياسات الإدراج التي تكتفي بـ«مسجَّل دخوله» بلا ربط عمود الملكية،
-- فأي عضو يقدر ينشئ صفاً منسوباً لغيره. الجدولان غير مستعملين في iOS ولا
-- Flutter ولا الويب (تُحقّق بالبحث)، فالتضييق بلا أثر على التطبيقات.

-- user_timeline: محطات حياة العضو — كان أي عضو يكتب محطة في سجلّ عضو آخر.
drop policy if exists user_timeline_insert_authenticated on public.user_timeline;
create policy user_timeline_insert_self on public.user_timeline
for insert to authenticated
with check (
  user_id = auth.uid()
  or public.current_user_role() = any (array['owner','admin'])
);

-- family_story_views: سجلّ المشاهدة — كان يُزوَّر باسم مشاهِد آخر.
drop policy if exists story_views_insert on public.family_story_views;
create policy story_views_insert_self on public.family_story_views
for insert to authenticated
with check (viewer_id = auth.uid());
