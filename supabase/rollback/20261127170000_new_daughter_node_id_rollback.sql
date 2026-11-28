-- تراجع 20261127170000_new_daughter_node_id — يعيد link_woman_account كما في 20261024181856 حرفياً (عقدة جديدة بـ gen_random_uuid()).
-- العُقد التي أُنشئت بعده بمعرّف ملف صاحبتها تبقى كما هي (لا فكّ لأي رابط).

do $mig$
declare d text := pg_get_functiondef('public.link_woman_account(uuid,uuid,uuid,text)'::regprocedure); n text;
begin
  n := replace(d, $x$    -- عقدة البنت بمعرّف ملفها (20261127170000) — النسخ القديمة تجدها به
    if exists (select 1 from public.women_members x where x.id = p.id) then
      raise exception 'لها عقدة في شجرة النساء — اربطها بها' using errcode = 'P0001', hint = 'node_exists';
    end if;
    insert into public.women_members (id, first_name, full_name, parent_id, gender, sort_order)
    values (p.id, nm,$x$, $x$    insert into public.women_members (id, first_name, full_name, parent_id, gender, sort_order)
    values (gen_random_uuid(), nm,$x$);
  if n = d then raise exception 'link_woman_account: نص الحي تغيّر — راجع التراجع'; end if;
  execute n;
end $mig$;

comment on function public.link_woman_account(uuid, uuid, uuid, text) is
  'دخول النساء: ربط طلب انضمام أنثى بعقدتها في شجرة النساء (أو عقدة جديدة تحت أبيها) وتفعيل حسابها — للمالك/المدير/المراقب؛ hint: not_allowed | request_not_found | already_handled | not_female | has_father | node_taken | not_female_node | no_father | name_required';
