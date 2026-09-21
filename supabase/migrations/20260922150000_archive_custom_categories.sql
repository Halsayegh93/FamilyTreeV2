-- تصنيفات مكتبة جديدة بدون كسر النسخة القديمة (طلب المالك)
--
-- النسخة المنشورة من التطبيق تقبل في family_archive.category القيم الأربع فقط،
-- وأي قيمة غيرها تعطّل المكتبة كلها عندها. لذلك:
--   • category يبقى إحدى القيم الأربع (قيد الجدول كما هو) — للتصنيف الجديد يُحفظ 'other'
--   • category_key يحفظ التصنيف الحقيقي الجديد (من content_categories)
-- النسخة القديمة ترى العنصر تحت «أخرى»، والنسخة الجديدة تقرأ category_key أولاً.

alter table public.family_archive
  add column if not exists category_key text;

comment on column public.family_archive.category_key is
  'تصنيف مكتبة مخصّص (content_categories.key حيث section=archive). يُقرأ قبل category. category يبقى other للتوافق مع النسخة القديمة.';

-- لا يُقبل مفتاح غير موجود في جدول التصنيفات
create or replace function public.family_archive_validate_category_key()
returns trigger language plpgsql as $$
begin
  if new.category_key is not null and not exists (
    select 1 from public.content_categories c
    where c.section = 'archive' and c.key = new.category_key
  ) then
    raise exception 'unknown archive category: %', new.category_key using errcode = '23514';
  end if;
  return new;
end $$;

drop trigger if exists family_archive_category_key_check on public.family_archive;
create trigger family_archive_category_key_check
  before insert or update of category_key on public.family_archive
  for each row execute function public.family_archive_validate_category_key();
