-- مُستخرَجة من سجل الإنتاج (supabase_migrations.schema_migrations)
-- كانت مطبَّقة على القاعدة لكن ملفها مفقود من المستودع.

-- يسمح للعضو (أي دور) بربط أنثى موجودة (غير مرتبطة بزوج) كزوجة له — مقيّد على عقدته فقط.
-- مطابق لنمط set_self_mother (SECURITY DEFINER + التحقق من الهدف). ضروري عشان
-- خيار «زوجة من العائلة» في «عائلتي» يشتغل للعضو العادي (الكتابة المباشرة على
-- women_members محصورة بالمدير عبر RLS، وهذه الدالة تتجاوزها بأمان وبنطاق محدود).
create or replace function public.set_self_wife(p_wife_id uuid)
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
  if p_wife_id is null then
    raise exception 'wife_required';
  end if;
  -- الهدف لازم يكون أنثى، غير مرتبطة بزوج، وليست العضو نفسه
  if not exists (
    select 1 from public.women_members w
    where w.id = p_wife_id
      and w.gender = 'female'
      and w.husband_id is null
      and w.id <> me
  ) then
    raise exception 'invalid_wife';
  end if;
  update public.women_members set husband_id = me where id = p_wife_id;
end;
$function$;

grant execute on function public.set_self_wife(uuid) to authenticated;;
