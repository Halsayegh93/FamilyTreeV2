-- فلتر الكلمات غير اللائقة على باقي نصوص الأعضاء (قرار المالك ٢٠٢٦-١٠-٢٩ «نعم اصلح»، Apple 1.2):
-- نفس contains_blocked_word وقائمة app_config.blocked_words، ونفس hint = 'objectionable' كتعليقات الأخبار.
-- يُفحص النص فقط حين يُضاف أو يتغيّر (تعديل عمود آخر في صف قديم لا يُرفض).
-- الرسالة من app_config.blocked_words_message_general (تعليقات الأخبار تبقى على blocked_words_message).

insert into public.app_config (key, value, default_value, kind, max_length, category, label_ar, help_ar, is_public, sort)
values ('blocked_words_message_general',
        to_jsonb('النص فيه كلمات غير لائقة — عدّله ثم أرسله.'::text),
        to_jsonb('النص فيه كلمات غير لائقة — عدّله ثم أرسله.'::text),
        'text', 200, 'general', 'رسالة رفض النص غير اللائق',
        'تظهر للعضو إذا كتب كلمة من القائمة المحظورة في اسم ديوانية أو مشروع أو نبذة أو وصف أو خبر.',
        false, 91)
on conflict (key) do nothing;

create or replace function public.trg_text_filter()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare
  col  text;
  n    jsonb := to_jsonb(new);
  o    jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) end;
  msg  text;
begin
  foreach col in array tg_argv loop
    if n ? col and n->col is not null and jsonb_typeof(n->col) <> 'null'
       and (o is null or (n->col) is distinct from (o->col))
       and public.contains_blocked_word(case when jsonb_typeof(n->col) = 'string' then n->>col else (n->col)::text end) then
      msg := public.config_text('blocked_words_message_general', 'النص فيه كلمات غير لائقة — عدّله ثم أرسله.');
      raise exception '%', msg using errcode = 'P0001', hint = 'objectionable', detail = tg_table_name || '.' || col;
    end if;
  end loop;
  return new;
end $$;

drop trigger if exists trg_diwaniyas_text_filter on public.diwaniyas;
create trigger trg_diwaniyas_text_filter before insert or update on public.diwaniyas
  for each row execute function public.trg_text_filter('name', 'title', 'owner_name', 'address', 'schedule_text', 'timing');

drop trigger if exists trg_projects_text_filter on public.projects;
create trigger trg_projects_text_filter before insert or update on public.projects
  for each row execute function public.trg_text_filter('title', 'description', 'owner_name');

drop trigger if exists trg_profiles_text_filter on public.profiles;
create trigger trg_profiles_text_filter before insert or update of bio, bio_json on public.profiles
  for each row execute function public.trg_text_filter('bio', 'bio_json');

drop trigger if exists trg_family_archive_text_filter on public.family_archive;
create trigger trg_family_archive_text_filter before insert or update on public.family_archive
  for each row execute function public.trg_text_filter('title', 'description');

drop trigger if exists trg_family_stories_text_filter on public.family_stories;
create trigger trg_family_stories_text_filter before insert or update on public.family_stories
  for each row execute function public.trg_text_filter('caption');

drop trigger if exists trg_member_gallery_text_filter on public.member_gallery_photos;
create trigger trg_member_gallery_text_filter before insert or update on public.member_gallery_photos
  for each row execute function public.trg_text_filter('caption');

drop trigger if exists trg_gallery_photos_text_filter on public.gallery_photos;
create trigger trg_gallery_photos_text_filter before insert or update on public.gallery_photos
  for each row execute function public.trg_text_filter('caption');

drop trigger if exists trg_news_text_filter on public.news;
create trigger trg_news_text_filter before insert or update on public.news
  for each row execute function public.trg_text_filter('content', 'poll_question', 'poll_options');
