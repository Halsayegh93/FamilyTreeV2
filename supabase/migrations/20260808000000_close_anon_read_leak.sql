-- إغلاق قراءة مجهولة مؤكَّدة: ثلاث سياسات SELECT بـUSING(true) على الدور public
-- (أي anon أيضاً). السياسات المتساهلة تُجمع بـ«أو» فكانت تُلغي السياسات الصارمة
-- المجاورة لها. مُختبَر: family_stories و family_story_views كانتا تُقرآن بالمفتاح
-- العام بلا تسجيل دخول؛ member_gallery_photos نفس الثغرة لكنه فارغ اليوم فقط.

-- ١) حذف السياسات المفتوحة (لكل جدول سياسة أدقّ باقية تغطّي الاستعمال الفعلي)
drop policy if exists family_stories_select        on public.family_stories;
drop policy if exists story_views_select           on public.family_story_views;
drop policy if exists member_gallery_photos_select on public.member_gallery_photos;

-- ٢) family_story_views لم يبقَ لها سياسة قراءة — سياسة معقولة بدل صمت تام
create policy story_views_select_self_or_moderator on public.family_story_views
for select to authenticated
using (viewer_id = auth.uid() or public.is_moderator());

-- ٣) بوّابة مُقيِّدة (تُجمع بـ«و») على الثلاثة — تمنع أي سياسة متساهلة مستقبلية
--    من إعادة فتحها للزائر، على نمط require_authenticated_* الموجود أصلاً.
drop policy if exists require_authenticated_family_stories on public.family_stories;
create policy require_authenticated_family_stories on public.family_stories
as restrictive for all to public using (auth.uid() is not null);

drop policy if exists require_authenticated_story_views on public.family_story_views;
create policy require_authenticated_story_views on public.family_story_views
as restrictive for all to public using (auth.uid() is not null);

drop policy if exists require_authenticated_member_gallery on public.member_gallery_photos;
create policy require_authenticated_member_gallery on public.member_gallery_photos
as restrictive for all to public using (auth.uid() is not null);
