-- أرقام عامة مجمّعة للموقع التجاري (موافقة المالك ٢٠٢٦-١٠-٢٠: «عدد الأفراد والأجيال كأرقام إجمالية»، سنة التأسيس ١٩٨٥
-- ثابت في الموقع نفسه). ترجع أرقام إجمالية فقط — بلا أسماء ولا معرّفات — فتُتاح للزائر (anon).
--   members     = أعضاء الشجرة المعدودون (نفس applyCountableFilters في الموقع وفلتر شجرة iOS)
--   generations = أطول سلسلة أب ← ابن في الشجرة (حد ٦٠ للحماية من الحلقات)
-- التراجع: supabase/rollback/20261020120000_public_family_stats_rollback.sql
create or replace function public.public_family_stats() returns jsonb
language sql security definer stable set search_path = '' as $$
  with recursive chain as (
    select id, 1 as depth from public.profiles
     where father_id is null and coalesce(btrim(full_name), '') <> ''
    union all
    select p.id, c.depth + 1 from public.profiles p join chain c on p.father_id = c.id where c.depth < 60
  )
  select jsonb_build_object(
    'members', (select count(*) from public.profiles
                 where role <> 'pending' and coalesce(status, '') <> 'frozen'
                   and not coalesce(is_hidden_from_tree, false) and coalesce(btrim(full_name), '') <> ''),
    'generations', (select coalesce(max(depth), 0) from chain)
  );
$$;
revoke all on function public.public_family_stats() from public;
grant execute on function public.public_family_stats() to anon, authenticated;
