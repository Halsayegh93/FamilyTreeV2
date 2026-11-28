-- تراجع 20261128170000_server_speed (لم يُشغَّل — للطوارئ فقط).
-- ١) السياسات: كل `( SELECT auth.uid() AS uid)` (وكذلك jwt و role) في سياسات public يرجع `auth.uid()` غير مغلّف.
--    تحقّق ٢٠٢٦-١١-٢٨ قبل كتابته: في الحي ٨٢ سياسة بالشكل المغلّف و٠ بالشكل غير المغلّف — أي أن الـ٨٢ كلها من هذا الترحيل،
--    فلا تُفكّ سياسة كانت مغلّفة قبله. (أي سياسة جديدة تُكتب مغلّفة بعد اليوم ستُفكّ أيضاً — راجع العدد قبل التشغيل.)
-- ٢) الفهارس: يحذف idx_fk_* في public (٣٧ في الحي يوم الكتابة، كلها من هذا الترحيل).
-- المعنى في الحالتين واحد (من يرى ماذا لا يتغيّر)؛ التراجع يعيد البطء فقط.
begin;

do $$
declare r record; v_qual text; v_check text; v_sql text; n int := 0;
begin
  for r in
    select schemaname, tablename, policyname, qual, with_check
      from pg_policies
     where schemaname = 'public'
       and (coalesce(qual, '') || coalesce(with_check, '')) ~ '\( SELECT auth\.(uid|jwt|role)\(\) AS (uid|jwt|role)\)'
  loop
    v_qual  := regexp_replace(r.qual,       '\( SELECT auth\.(uid|jwt|role)\(\) AS (uid|jwt|role)\)', 'auth.\1()', 'g');
    v_check := regexp_replace(r.with_check, '\( SELECT auth\.(uid|jwt|role)\(\) AS (uid|jwt|role)\)', 'auth.\1()', 'g');
    v_sql := format('alter policy %I on %I.%I', r.policyname, r.schemaname, r.tablename);
    if v_qual is not null then v_sql := v_sql || ' using (' || v_qual || ')'; end if;
    if v_check is not null then v_sql := v_sql || ' with check (' || v_check || ')'; end if;
    execute v_sql;
    n := n + 1;
  end loop;
  raise notice 'سياسات أُعيدت: %', n;
end $$;

do $$
declare r record; n int := 0;
begin
  for r in select schemaname, indexname from pg_indexes where schemaname = 'public' and indexname like 'idx\_fk\_%' loop
    execute format('drop index if exists %I.%I', r.schemaname, r.indexname);
    n := n + 1;
  end loop;
  raise notice 'فهارس حُذفت: %', n;
end $$;

commit;
