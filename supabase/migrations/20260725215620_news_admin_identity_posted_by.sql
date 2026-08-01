-- مُستخرَجة من سجل الإنتاج (supabase_migrations.schema_migrations)
-- كانت مطبَّقة على القاعدة لكن ملفها مفقود من المستودع.

-- هوية «إدارة العائلة» مضمونة على السيرفر:
-- منشور الإدارة يُحفظ بـ author_id = NULL حتى لا يستطيع أي عميل (قديم أو جديد)
-- استبدال الاسم باسم العضو عبر البحث في الشجرة — فيقع حتماً على author_name.
-- والمالك الحقيقي يُحفظ في posted_by للصلاحيات والتدقيق.
alter table public.news
  add column if not exists posted_by uuid references public.profiles(id) on delete set null;

update public.news set posted_by = author_id where posted_by is null and author_id is not null;

create index if not exists news_posted_by_idx on public.news (posted_by);

-- الإدراج: إمّا باسم العضو (كما كان)، أو بهوية الإدارة (author_id فارغ) لفريق الإدارة
drop policy if exists news_insert_authenticated on public.news;
create policy news_insert_authenticated on public.news
for insert with check (
  auth.uid() is not null and (
    author_id = auth.uid()
    or (
      author_id is null
      and posted_by = auth.uid()
      and current_user_role() = any (array['owner','admin','monitor','supervisor'])
    )
  )
);

-- القراءة والحذف يعترفان بـ posted_by حتى يبقى صاحب المنشور مالكاً له
drop policy if exists news_select_approved_or_owner_or_moderator on public.news;
create policy news_select_approved_or_owner_or_moderator on public.news
for select using (
  approval_status = 'approved'
  or author_id = auth.uid()
  or posted_by = auth.uid()
  or current_user_role() = any (array['supervisor','monitor','admin','owner'])
);

drop policy if exists news_delete_owner_or_moderator on public.news;
create policy news_delete_owner_or_moderator on public.news
for delete using (
  author_id = auth.uid()
  or posted_by = auth.uid()
  or current_user_role() = any (array['supervisor','admin'])
);;
