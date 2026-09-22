-- عدد العناصر في كل تصنيف + حذف التصنيف نهائياً (طلب المالك)
--
-- العدد: الأخبار حسب news.type، والمكتبة حسب category_key أو category.
-- الحذف النهائي: للمالك فقط، ولا يُسمح إلا إذا كان التصنيف فارغاً (صفر عناصر)،
-- ولا تُحذف التصنيفات الأساسية التي يعتمد عليها التطبيق:
--   «خبر» (النوع الافتراضي) و«تصويت» (الاستطلاعات) و«أخرى» في المكتبة.

create or replace function public.content_category_counts()
returns table (section text, key text, items int)
language sql
stable
security definer
set search_path = public
as $$
  select 'news'::text, n.type, count(*)::int
  from public.news n
  group by n.type
  union all
  select 'archive'::text, coalesce(a.category_key, a.category), count(*)::int
  from public.family_archive a
  group by coalesce(a.category_key, a.category);
$$;

revoke all on function public.content_category_counts() from public, anon;
grant execute on function public.content_category_counts() to authenticated;

create or replace function public.delete_content_category(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_section text;
  v_key text;
  v_items int;
begin
  if coalesce(public.current_user_role(), '') <> 'owner' then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  select section, key into v_section, v_key from public.content_categories where id = p_id;
  if v_key is null then
    raise exception 'not_found' using errcode = 'P0002';
  end if;

  if (v_section = 'news' and v_key in ('خبر', 'تصويت'))
     or (v_section = 'archive' and v_key = 'other') then
    raise exception 'protected_category' using errcode = '23514';
  end if;

  if v_section = 'news' then
    select count(*) into v_items from public.news where type = v_key;
  else
    select count(*) into v_items from public.family_archive
      where coalesce(category_key, category) = v_key;
  end if;

  if v_items > 0 then
    raise exception 'category_not_empty:%', v_items using errcode = '23514';
  end if;

  delete from public.content_categories where id = p_id;
end $$;

revoke all on function public.delete_content_category(uuid) from public, anon;
grant execute on function public.delete_content_category(uuid) to authenticated;
