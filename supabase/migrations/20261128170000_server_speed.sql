-- مطبَّق على الحي ٢٠٢٦-١١-٢٨ بعد تجربة begin…rollback: ٣٧ فهرساً، ٨٢ سياسة، وما يراه عضو ومالك في ٨ جداول لم يتغيّر (٠ فروق).
-- سرعة السيرفر (طلب المالك ٢٠٢٦-١١-٢٨ «حسن سرعة السيرفر»): تنبيهات أداء Supabase.
-- ١) فهرس لكل مفتاح أجنبي بلا فهرس (٣٧) — حذف/تعديل الصفّ الأب كان يمسح الجدول كاملاً للتحقق.
-- ٢) سياسات RLS: `auth.uid()`/`auth.jwt()`/`auth.role()` تُستدعى مرة للاستعلام بدل مرة لكل صف
--    (`(select auth.uid())` — نفس المعنى حرفياً؛ ٨٢ سياسة). لا تغيير في من يرى ماذا.

do $$
declare r record; v_cols text; v_name text;
begin
  for r in
    select c.conrelid::regclass as tbl, c.conname,
           (select string_agg(quote_ident(a.attname), ', ' order by k.ord)
              from unnest(c.conkey) with ordinality k(n, ord)
              join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.n) as cols
      from pg_constraint c join pg_namespace n on n.oid = c.connamespace
     where c.contype = 'f' and n.nspname = 'public'
       and not exists (select 1 from pg_index i
                        where i.indrelid = c.conrelid
                          and (i.indkey::int2[])[0:array_length(c.conkey, 1) - 1] = c.conkey)
  loop
    v_name := left('idx_fk_' || r.conname, 63);
    execute format('create index if not exists %I on %s (%s)', v_name, r.tbl, r.cols);
  end loop;
end $$;

do $$
declare r record; v_qual text; v_check text; v_sql text;
begin
  for r in
    select schemaname, tablename, policyname, qual, with_check
      from pg_policies
     where schemaname = 'public'
       and (coalesce(qual, '') || coalesce(with_check, '')) ~ '(?<!SELECT )auth\.(uid|jwt|role)\(\)'
  loop
    v_qual  := regexp_replace(r.qual,       '(?<!SELECT )auth\.(uid|jwt|role)\(\)', '(SELECT auth.\1())', 'g');
    v_check := regexp_replace(r.with_check, '(?<!SELECT )auth\.(uid|jwt|role)\(\)', '(SELECT auth.\1())', 'g');
    v_sql := format('alter policy %I on %I.%I', r.policyname, r.schemaname, r.tablename);
    if v_qual is not null then v_sql := v_sql || ' using (' || v_qual || ')'; end if;
    if v_check is not null then v_sql := v_sql || ' with check (' || v_check || ')'; end if;
    execute v_sql;
  end loop;
end $$;
