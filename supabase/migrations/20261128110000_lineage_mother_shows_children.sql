-- مطبَّق على الحي ٢٠٢٦-١١-٢٨ بعد تجربة begin…rollback (سهيلة تُشغَّل من جديد عند تحديث صف حسين)
-- قرار المالك ٢٠٢٦-١١-٢٨ («١» = تلقائي): حين يُعتمد ابن بنت أو بنت بنت (صفّ نسب له عقدة في شجرة النساء بأمّ)،
-- يُشغَّل لأمّه «إظهار الزوج والأبناء» (children_shown + spouse_shown) — وإلا يبقى مخفياً عن الأعضاء تحتها
-- (السبب: حسين الصاغة تحت سهيلة وأسماء تحت منال كانا مخفيّين، وأُصلحا يدوياً اليوم).
-- لا يُطفئ شيئاً أبداً؛ يشغّل فقط ما ليس true.
-- التراجع: drop trigger trg_lineage_mother_shows_children on public.daughter_son_lineage; drop function private.lineage_mother_shows_children();
create or replace function private.lineage_mother_shows_children()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare v_mother uuid;
begin
  if new.completed_at is null then return new; end if;
  select w.mother_id into v_mother
    from public.women_members w
   where w.id = coalesce(new.women_node_id, new.profile_id);
  if v_mother is not null then
    update public.women_members
       set children_shown = true, spouse_shown = true
     where id = v_mother
       and (children_shown is distinct from true or spouse_shown is distinct from true);
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_lineage_mother_shows_children on public.daughter_son_lineage;
create trigger trg_lineage_mother_shows_children
  after insert or update of completed_at, women_node_id on public.daughter_son_lineage
  for each row execute function private.lineage_mother_shows_children();

-- ما سبق (الموجود الآن): أمّهات كل صفوف النسب المكتملة
update public.women_members m
   set children_shown = true, spouse_shown = true
 where (m.children_shown is distinct from true or m.spouse_shown is distinct from true)
   and m.id in (select w.mother_id from public.daughter_son_lineage d
                  join public.women_members w on w.id = coalesce(d.women_node_id, d.profile_id)
                 where d.completed_at is not null and w.mother_id is not null);
