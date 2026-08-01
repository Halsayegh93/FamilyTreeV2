-- دالة بحث بالاسم أثناء التسجيل — تتجاوز RLS
-- مستخدم جديد (pending) لا يستطيع رؤية بيانات الأعضاء بسبب سياسة profiles_select_self_or_active
-- هذه الدالة security definer تعمل بصلاحيات كاملة وتُرجع فقط UUID للأعضاء المتطابقين

create or replace function public.search_members_by_name(p_query text)
returns table (member_id uuid, full_name text, match_score bigint)
language sql
security definer
stable
set search_path = public
as $$
  with parts as (
    -- تقسيم الاسم إلى أجزاء وإزالة الأجزاء القصيرة
    select unnest(string_to_array(trim(p_query), ' ')) as part
  ),
  valid_parts as (
    select part from parts where length(trim(part)) >= 2
  ),
  matches as (
    -- لكل عضو في الشجرة: عدد أجزاء الاسم المتطابقة
    select
      p.id as mid,
      p.full_name as fname,
      count(*) as score
    from public.profiles p
    cross join valid_parts vp
    where p.full_name ilike '%' || vp.part || '%'
      and p.role not in ('pending')     -- أعضاء الشجرة فقط (ليس طلبات معلقة)
    group by p.id, p.full_name
  ),
  total_parts as (
    select count(*) as cnt from valid_parts
  )
  select
    m.mid,
    m.fname,
    m.score
  from matches m, total_parts tp
  where m.score >= least(2, tp.cnt)   -- يجب مطابقة جزأين على الأقل
  order by m.score desc
  limit 10;
$$;

-- منح صلاحية الاستدعاء لأي مستخدم مصادق عليه (بما فيهم pending)
grant execute on function public.search_members_by_name(text) to authenticated;
