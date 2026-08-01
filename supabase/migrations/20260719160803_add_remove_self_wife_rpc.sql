-- مُستخرَجة من سجل الإنتاج (supabase_migrations.schema_migrations)
-- كانت مطبَّقة على القاعدة لكن ملفها مفقود من المستودع.

-- يسمح للعضو (أي دور) بحذف/فكّ زوجته من «عائلتي» — مقيّد على عقدته فقط.
-- يفكّ الارتباط (husband_id = null)، ويحذف الصف فقط إذا صار «يتيماً» (زوجة أضيفت بالاسم
-- بلا أي روابط أخرى) لتفادي بقايا بلا معنى. مطابق لفلسفة set_self_mother.
create or replace function public.remove_self_wife(p_wife_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  me uuid := public.my_women_node();
begin
  if me is null then
    raise exception 'no_node';
  end if;
  -- لازم تكون زوجة المستخدم فعلاً
  if not exists (
    select 1 from public.women_members where id = p_wife_id and husband_id = me
  ) then
    raise exception 'not_your_wife';
  end if;

  -- فكّ الارتباط أولاً
  update public.women_members set husband_id = null where id = p_wife_id;

  -- إذا صارت بلا أي روابط (أب/أم/حساب) وبلا أبناء يشيرون لها → احذفها
  if not exists (
        select 1 from public.women_members
        where id = p_wife_id
          and (parent_id is not null or mother_id is not null or linked_user_id is not null)
      )
     and not exists (
        select 1 from public.women_members c
        where c.parent_id = p_wife_id or c.mother_id = p_wife_id
      ) then
    delete from public.women_members where id = p_wife_id;
  end if;
end;
$function$;

grant execute on function public.remove_self_wife(uuid) to authenticated;;
