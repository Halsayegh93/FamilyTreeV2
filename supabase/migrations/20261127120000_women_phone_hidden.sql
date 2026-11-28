-- رقم المرأة مخفي تلقائياً عن الأعضاء، ويظهر للإدارة (طلب المالك ٢٠٢٦-١١-٢٧ «اذا في ارقام عند النساء يكون مخفي
-- مطبَّق على الحي ٢٠٢٦-١١-٢٧ بعد تجربة begin…rollback (النساء الظاهرات ٠، الرجال المخفيون ١٣ كما هم).
-- تلقائي وعند الادارة يظهر»).
-- القراءة عبر members_masked: الرقم يظهر حين is_phone_hidden = false، أو لصاحبه، أو للإدارة (is_team: المالك والمدير
-- والمراقب والمشرف). فيكفي أن يبقى is_phone_hidden = true لكل أنثى — كان ٤٧ من ٤٨ كذلك، وواحدة ظاهرة.
-- المشغّل يفرضه عند الإدراج وعند تغيير الجنس أو الرقم أو العلم نفسه، فلا تُظهره التطبيقات ولا صاحبته.
-- التراجع: rollback/20261127120000_women_phone_hidden_rollback.sql

create or replace function private.women_phone_hidden()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if lower(coalesce(new.gender, '')) = 'female' then
    new.is_phone_hidden := true;
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_women_phone_hidden on public.profiles;
create trigger trg_women_phone_hidden
  before insert or update of gender, phone_number, is_phone_hidden on public.profiles
  for each row execute function private.women_phone_hidden();

-- الموجود: من كانت ظاهرة تُخفى (لا يمسّ غير هذا العمود)
update public.profiles
   set is_phone_hidden = true
 where lower(coalesce(gender, '')) = 'female'
   and coalesce(is_phone_hidden, false) = false;
