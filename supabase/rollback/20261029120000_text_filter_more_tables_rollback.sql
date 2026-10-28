-- تراجع 20261029120000_text_filter_more_tables
drop trigger if exists trg_diwaniyas_text_filter on public.diwaniyas;
drop trigger if exists trg_projects_text_filter on public.projects;
drop trigger if exists trg_profiles_text_filter on public.profiles;
drop trigger if exists trg_family_archive_text_filter on public.family_archive;
drop trigger if exists trg_family_stories_text_filter on public.family_stories;
drop trigger if exists trg_member_gallery_text_filter on public.member_gallery_photos;
drop trigger if exists trg_gallery_photos_text_filter on public.gallery_photos;
drop trigger if exists trg_news_text_filter on public.news;
drop function if exists public.trg_text_filter();
delete from public.app_config where key = 'blocked_words_message_general';
