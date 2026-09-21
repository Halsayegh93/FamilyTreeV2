-- التصنيفات قابلة للتعديل من «إعدادات التطبيق» (طلب المالك)
--
-- بدل تصنيفات ثابتة في كود التطبيقين: جدول واحد لكل الأقسام.
--   section    — القسم: news (الأخبار) | archive (مكتبة العائلة)
--   key        — القيمة المخزّنة في المحتوى نفسه ولا تتغيّر أبداً
--                (news.type يخزّن الاسم العربي، family_archive.category رمزاً إنجليزياً)
--   name_ar/en — الاسم المعروض (قابل للتعديل)
--   icon_key   — رمز أيقونة من مجموعة ثابتة يعرفها التطبيقان
--   color_key  — مفتاح لون من لوحة ثابتة يعرفها التطبيقان
--   is_active  — «إخفاء» التصنيف: يختفي من الاختيارات ويبقى المحتوى القديم بتصنيفه
-- لا حذف نهائي — الإخفاء فقط (قرار المالك).

create table if not exists public.content_categories (
  id          uuid primary key default gen_random_uuid(),
  section     text not null check (section in ('news', 'archive')),
  key         text not null,
  name_ar     text not null check (length(btrim(name_ar)) between 1 and 30),
  name_en     text not null check (length(btrim(name_en)) between 1 and 30),
  icon_key    text not null,
  color_key   text not null,
  sort_order  int  not null default 0,
  is_active   boolean not null default true,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references public.profiles(id) on delete set null,
  unique (section, key)
);

alter table public.content_categories enable row level security;

drop policy if exists content_categories_select on public.content_categories;
create policy content_categories_select on public.content_categories
  for select to authenticated using (true);

-- التعديل للمالك فقط — مثل باقي «إعدادات التطبيق»
drop policy if exists content_categories_insert_owner on public.content_categories;
create policy content_categories_insert_owner on public.content_categories
  for insert to authenticated
  with check (public.current_user_role() = 'owner');

drop policy if exists content_categories_update_owner on public.content_categories;
create policy content_categories_update_owner on public.content_categories
  for update to authenticated
  using (public.current_user_role() = 'owner')
  with check (public.current_user_role() = 'owner');

grant select, insert, update on public.content_categories to authenticated;

-- البذرة: نفس التصنيفات والأيقونات والألوان الحالية في التطبيقين
insert into public.content_categories (section, key, name_ar, name_en, icon_key, color_key, sort_order) values
  ('news', 'خبر',    'خبر',    'News',         'newspaper.fill',     'navy',         0),
  ('news', 'إعلان',  'إعلان',  'Announcement', 'megaphone.fill',     'announcement', 1),
  ('news', 'زواج',   'زواج',   'Wedding',      'heart.fill',         'wedding',      2),
  ('news', 'مولود',  'مولود',  'Newborn',      'figure.child',       'birth',        3),
  ('news', 'وفاة',   'وفاة',   'Obituary',     'heart.slash.fill',   'death',        4),
  ('news', 'تهنئة',  'تهنئة',  'Congrats',     'hands.clap.fill',    'congrats',     5),
  ('news', 'دعوة',   'دعوة',   'Invitation',   'envelope.open.fill', 'invitation',   6),
  ('news', 'تذكير',  'تذكير',  'Reminder',     'bell.badge.fill',    'reminder',     7),
  ('news', 'تصويت',  'تصويت',  'Poll',         'chart.bar.fill',     'vote',         8),
  ('archive', 'documents',  'وثائق',     'Documents',  'doc.text.fill',     'info',  0),
  ('archive', 'books',      'كتب',       'Books',      'book.closed.fill',  'gold',  1),
  ('archive', 'old_photos', 'صور قديمة', 'Old Photos', 'photo.stack.fill',  'rose',  2),
  ('archive', 'other',      'أخرى',      'Other',      'folder.fill',       'gray',  3)
on conflict (section, key) do nothing;
