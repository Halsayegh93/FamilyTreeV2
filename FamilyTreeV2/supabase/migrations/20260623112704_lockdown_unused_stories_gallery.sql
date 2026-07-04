-- ميزتان محذوفتان من التطبيق (family_stories, member_gallery_photos):
-- نقفل الكتابة عليها بالكامل (الإدارة فقط) لإزالة سطح الهجوم.

-- family_stories — إزالة سياسات الإضافة المفتوحة، وحصرها بالإدارة.
drop policy if exists family_stories_insert on public.family_stories;
drop policy if exists stories_insert on public.family_stories;
create policy family_stories_insert on public.family_stories for insert to authenticated
  with check (public.is_moderator());

-- member_gallery_photos — نفس الشيء.
drop policy if exists member_gallery_photos_insert on public.member_gallery_photos;
drop policy if exists member_gallery_insert_self_or_moderator on public.member_gallery_photos;
create policy member_gallery_photos_insert on public.member_gallery_photos for insert to authenticated
  with check (public.is_moderator());;
