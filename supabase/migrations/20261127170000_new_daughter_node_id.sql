-- «بنت جديدة» من مربّع «الربط» في «الوارد» (المالك ٢٠٢٦-١١-٢٧، مربّعات الإدارة R2):
-- مطبَّق على الحي ٢٠٢٦-١١-٢٧ بعد تجربة begin…rollback.
-- عقدة شجرة النساء الجديدة لحساب بنت من العائلة تُنشأ **بمعرّف ملفها** (id = profiles.id) و`linked_user_id` = ملفها —
-- النسخ القديمة من التطبيق تجد عقدة المرأة بمعرّفها (`my_women_node` / `women_members.id = حسابها`).
-- التغيير الوحيد في link_woman_account (20261024181856): فرع «عقدة جديدة» يكتب `p.id` بدل `gen_random_uuid()`،
-- وإن وُجدت عقدة بمعرّفها من قبل يُرفض بـ hint = node_exists (يُربط بها من «ربط» لا بعقدة ثانية).
-- الصلاحيات والحرّاس والإشعار والإغلاق كما هي حرفياً (المالك/المدير/المراقب، الطلب معلّق، أنثى بلا أب في شجرة الرجال).
-- NOT APPLIED — يطبّقه المدير بعد تجربة begin…rollback وموافقة المالك.
-- التراجع: rollback/20261127170000_new_daughter_node_id_rollback.sql
-- تجربة: cd supabase/tests/family_links && node new_daughter_node_id.test.mjs

do $mig$
declare d text := pg_get_functiondef('public.link_woman_account(uuid,uuid,uuid,text)'::regprocedure); n text;
begin
  n := replace(d, $x$    insert into public.women_members (id, first_name, full_name, parent_id, gender, sort_order)
    values (gen_random_uuid(), nm,$x$, $x$    -- عقدة البنت بمعرّف ملفها (20261127170000) — النسخ القديمة تجدها به
    if exists (select 1 from public.women_members x where x.id = p.id) then
      raise exception 'لها عقدة في شجرة النساء — اربطها بها' using errcode = 'P0001', hint = 'node_exists';
    end if;
    insert into public.women_members (id, first_name, full_name, parent_id, gender, sort_order)
    values (p.id, nm,$x$);
  if n = d then raise exception 'link_woman_account: نص الحي تغيّر — راجع الترحيل'; end if;
  execute n;
end $mig$;

comment on function public.link_woman_account(uuid, uuid, uuid, text) is
  'دخول النساء: ربط طلب انضمام أنثى بعقدتها في شجرة النساء (أو عقدة جديدة بمعرّف ملفها تحت أبيها) وتفعيل حسابها — للمالك/المدير/المراقب؛ hint: not_allowed | request_not_found | already_handled | not_female | has_father | node_taken | not_female_node | no_father | name_required | node_exists';
