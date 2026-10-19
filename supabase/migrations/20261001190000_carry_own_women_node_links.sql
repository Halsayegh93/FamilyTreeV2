-- سدّ ثغرة في حماية روابط العائلة (٢٠٢٦-١٠-٠١ مساءً، بموافقة المالك)
--
-- ما حدث: أم المالك «هدى الصالح» انفصلت عنه يوم ٢٨/٩ — عند نقل ملفه لمعرّف جديد أنشأت
-- المزامنة عقدة جديدة له في شجرة النساء بلا أم (mirror_profile_to_women يضع الأب فقط)،
-- ثم حُذفت العقدة القديمة التي فيها أمّه. repoint_women_node (20261001150000) كان ينقل
-- من يشير للعقدة (الزوجة، البنات) لكنه لا ينقل روابط الشخص نفسه إذا كانت العقدة
-- الجديدة موجودة مسبقاً.
--
-- الإصلاح: العقدة الجديدة تأخذ ما ينقصها من القديمة — الأم واسمها، الأب، الزوج، الحالة
-- الاجتماعية — دون تغيير ما فيها أصلاً. (رُبطت أم المالك يدوياً بموافقته قبل هذا.)
-- التجربة: supabase/tests/family_links (سيناريوهات الأم في أول دخول و«ربط بالشجرة»).
-- التراجع: supabase/rollback/20261001190000_carry_own_women_node_links_rollback.sql

create or replace function public.repoint_women_node(p_old uuid, p_new uuid)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  c record;
begin
  if p_old is null or p_new is null or p_old = p_new
     or not exists (select 1 from public.women_members where id = p_old) then
    return;
  end if;

  -- للمعرّف الجديد عقدة (المزامنة تنشئها غالباً) — وإلا نسخة من القديمة
  insert into public.women_members
  select (jsonb_populate_record(
            null::public.women_members,
            to_jsonb(w) || jsonb_build_object('id', p_new)
         )).*
    from public.women_members w
   where w.id = p_old
  on conflict (id) do nothing;

  -- العقدة التي أنشأتها المزامنة تنقصها روابط الشخص نفسه — أمّه أولاً. تأخذ ما ينقصها
  -- من القديمة ولا يتغيّر ما فيها أصلاً.
  update public.women_members n
     set mother_id   = coalesce(n.mother_id,   o.mother_id),
         mother_name = coalesce(n.mother_name, o.mother_name),
         parent_id   = coalesce(n.parent_id,   o.parent_id),
         husband_id  = coalesce(n.husband_id,  o.husband_id),
         is_married  = coalesce(n.is_married,  o.is_married)
    from public.women_members o
   where n.id = p_new
     and o.id = p_old;

  for c in
    select con.conrelid::regclass as tbl, att.attname as col
      from pg_constraint con
      join pg_attribute att
        on att.attrelid = con.conrelid and att.attnum = con.conkey[1]
     where con.contype = 'f'
       and con.confrelid = 'public.women_members'::regclass
       and array_length(con.conkey, 1) = 1
  loop
    -- بلا تخطٍّ صامت: فشل أي نقل يُلغي العملية كلها بدل فصل أحد
    execute format('update %s set %I = $1 where %I = $2', c.tbl, c.col, c.col)
      using p_new, p_old;
  end loop;
end;
$function$;

revoke all on function public.repoint_women_node(uuid, uuid) from public, anon, authenticated;
