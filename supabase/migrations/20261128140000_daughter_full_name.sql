-- مطبَّق على الحي ٢٠٢٦-١١-٢٨ بعد تجربة begin…rollback (تعديل يكتب «أفنان» وحدها صار كاملاً، وبقي ٠ ناقص).
-- اسم البنت الكامل (طلب المالك ٢٠٢٦-١١-٢٨: «أفنان» محفوظة بالاسم الأول فقط تحت أبيها).
-- بنت لها أب في الشجرة (parent_id → profiles) واسمها المحفوظ كلمة واحدة = يُكمَّل
-- تلقائياً: «اسمها + اسم أبيها الكامل» — من أي مكان (آيفون، أندرويد، موقع، دالة).
-- العرض بالاسم الأول في الشجرة وقائمة البنات قرار التطبيقات، لا التخزين.
-- ثم إكمال الأسماء الخمسة الناقصة في الحي (زهراء، ماريا، أفنان، حوراء، بيبي).

create or replace function private.women_complete_daughter_name()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_father text; v_name text;
begin
  if new.parent_id is null or coalesce(new.is_outside_family, false) then return new; end if;
  v_name := btrim(coalesce(nullif(btrim(new.full_name), ''), new.first_name, ''));
  if v_name = '' or position(' ' in v_name) > 0 then return new; end if;
  select btrim(p.full_name) into v_father from public.profiles p where p.id = new.parent_id;
  if coalesce(v_father, '') = '' then return new; end if;
  new.full_name := v_name || ' ' || v_father;
  return new;
end $$;

drop trigger if exists trg_women_daughter_full_name on public.women_members;
create trigger trg_women_daughter_full_name
  before insert or update of full_name, first_name, parent_id on public.women_members
  for each row execute function private.women_complete_daughter_name();

-- إكمال الناقص الآن (الحارس أعلاه يكتب الاسم الكامل)
update public.women_members w set full_name = w.full_name
 where w.parent_id is not null and position(' ' in btrim(coalesce(w.full_name, ''))) = 0
   and exists (select 1 from public.profiles p where p.id = w.parent_id);
