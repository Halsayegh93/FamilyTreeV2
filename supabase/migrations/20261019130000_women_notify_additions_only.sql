-- إشعارات شجرة النساء: إضافة أو تعديل الإناث فقط (طلب المالك ٢٠٢٦-١٠-١٩ «ابى اي اضافة زوجة او بنت او ام في شجرة
-- النساء يصلني اشعار فقط» + «حتى تعديل مو اضافة للاناث في شجرة النساء»). كان المشغّل trg_women_activity_log يُشعر
-- الإدارة بكل إضافة وتعديل وحذف في women_members — ومنها نسخ الرجال (المرآة اللي يحدّثها السيرفر تلقائياً من profiles)،
-- فأي تعديل على رجل يطلع إشعار «تعديل في شجرة النساء».
-- الآن، للإناث (gender = female) بس:
--   • الإضافة: لها زوج ← «أُضيفت زوجة» + اسم الزوج · لها أب ← «أُضيفت بنت» + اسم الأب · غير ذلك (أم/بلا رابط بعد)
--     ← «أُضيفت إلى شجرة النساء»
--   • التعديل: الحقول اللي تغيّرت فعلاً كما كان (الاسم، الميلاد، الوفاة، الحالة الاجتماعية، الزوج، الأب، الأم، الإخفاء)
-- لا إشعار لنسخ الرجال، ولا للحذف. المستلمون كما كانوا (المالك والمدير والمراقب والمشرف المفعّلون، عدا من عدّل).
-- التراجع: supabase/rollback/20261019130000_women_notify_additions_only_rollback.sql
create or replace function public.log_women_change_to_activity()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  admin_id uuid;
  actor    uuid := auth.uid();
  who      text;
  rel      text;
  head     text;
  detail   text;
  k        text;
begin
  -- الإناث فقط، والإضافة أو التعديل فقط — نسخ الرجال والحذف بلا إشعار
  if tg_op = 'DELETE' or coalesce(lower(new.gender), 'female') <> 'female' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  who := coalesce(nullif(btrim(new.full_name), ''), nullif(btrim(new.first_name), ''), 'عضوة');

  if tg_op = 'INSERT' then
    head := 'إضافة في شجرة النساء';
    k    := 'women_add';
    if new.husband_id is not null then
      select nullif(btrim(coalesce(nullif(w.full_name, ''), w.first_name)), '') into rel
        from public.women_members w where w.id = new.husband_id;
      detail := 'أُضيفت زوجة: ' || who || coalesce(' — زوجة ' || rel, '');
    elsif new.parent_id is not null then
      select nullif(btrim(coalesce(nullif(w.full_name, ''), w.first_name)), '') into rel
        from public.women_members w where w.id = new.parent_id;
      detail := 'أُضيفت بنت: ' || who || coalesce(' — بنت ' || rel, '');
    else
      detail := 'أُضيفت إلى شجرة النساء: ' || who;
    end if;
  else
    -- التعديل: نسجّل الحقول التي تغيّرت فعلاً لا كل حفظ
    detail := '';
    if new.full_name  is distinct from old.full_name  then detail := detail || 'الاسم · '; end if;
    if new.birth_date is distinct from old.birth_date then detail := detail || 'تاريخ الميلاد · '; end if;
    if new.is_deceased is distinct from old.is_deceased then detail := detail || 'الوفاة · '; end if;
    if new.is_married is distinct from old.is_married then detail := detail || 'الحالة الاجتماعية · '; end if;
    if new.husband_id is distinct from old.husband_id then detail := detail || 'الزوج · '; end if;
    if new.parent_id  is distinct from old.parent_id  then detail := detail || 'الأب · '; end if;
    if new.mother_id  is distinct from old.mother_id  then detail := detail || 'الأم · '; end if;
    if new.is_hidden_from_tree is distinct from old.is_hidden_from_tree then detail := detail || 'الإخفاء · '; end if;
    -- لا شيء يستحقّ التسجيل (ترتيب/صورة/طابع زمني) → اخرج بلا ضجيج
    if detail = '' then return new; end if;
    head   := 'تعديل في شجرة النساء';
    detail := who || ' — ' || rtrim(detail, ' · ');
    k      := 'women_edit';
  end if;

  for admin_id in
    select id from public.profiles
    where role in ('owner','admin','monitor','supervisor')
      and status = 'active'
      and (actor is null or id <> actor)   -- لا يُخطَر من قام بالتغيير
  loop
    insert into public.notifications (target_member_id, title, body, kind, created_by, is_read)
    values (admin_id, head, detail, k, actor, false);
  end loop;

  return new;
end; $function$;
