-- التراجع عن 20261005180000_name_search_ignore_family — يعيد النسخة الحية قبل التعديل حرفياً
-- (pg_get_functiondef من السيرفر ٢٠٢٦-١٠-٠٥، مطابقة ببصمة md5).
CREATE OR REPLACE FUNCTION public.search_members_by_name(p_query text)
 RETURNS TABLE(member_id uuid, full_name text, match_score bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with query_parts as (
    -- تقسيم اسم المتقدم لأجزاء، إزالة الأقواس + المسافات الزائدة، استبعاد الأجزاء القصيرة
    select distinct trim(part) as part
    from unnest(
      string_to_array(
        regexp_replace(trim(p_query), '\(.*?\)|\s+', ' ', 'g'),
        ' '
      )
    ) as part
    where length(trim(part)) >= 2
  ),
  total as (
    select count(*)::int as cnt from query_parts
  ),
  member_top_parts as (
    -- أول 4 أجزاء من اسم كل عضو (الشخص + الأب + الجد + والد الجد)
    -- نزيل الأقواس والمسافات الزائدة لتطابق أنظف
    select
      p.id as mid,
      p.full_name as fname,
      (
        string_to_array(
          regexp_replace(trim(p.full_name), '\(.*?\)|\s+', ' ', 'g'),
          ' '
        )
      )[1:4] as top_parts
    from public.profiles p
    where p.role not in ('pending')
      and p.full_name is not null
      and length(trim(p.full_name)) > 0
  ),
  matches as (
    -- exact word match داخل أول 4 أجزاء من اسم العضو
    select
      mtp.mid,
      mtp.fname,
      count(distinct qp.part)::bigint as score
    from member_top_parts mtp
    cross join query_parts qp
    where qp.part = any(mtp.top_parts)
    group by mtp.mid, mtp.fname
  )
  select
    m.mid as member_id,
    m.fname as full_name,
    m.score as match_score
  from matches m, total t
  where m.score >= greatest(2, ceil(t.cnt::numeric * 0.75)::int)
  order by m.score desc, m.fname asc
  limit 10;
$function$;
