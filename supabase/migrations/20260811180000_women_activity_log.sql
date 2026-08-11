-- تسجيل حركة شجرة النساء في سجلّ النشاط.
-- السجلّ يقرأ من جدول notifications، وكانت تغييرات women_members لا تُسجَّل
-- إطلاقاً — فأي إضافة أو تعديل أو حذف في شجرة النساء يمرّ بلا أثر.
-- النمط مأخوذ من notify_admins_on_new_pending_member: صفّ لكل إداري نشط.

create or replace function public.log_women_change_to_activity()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  admin_id uuid;
  actor    uuid := auth.uid();
  who      text;
  head     text;
  detail   text;
  k        text;
begin
  if tg_op = 'DELETE' then
    who    := coalesce(nullif(old.full_name,''), old.first_name, 'عضوة');
    head   := 'حذف من شجرة النساء';
    detail := who || ' حُذف من شجرة النساء';
    k      := 'women_delete';

  elsif tg_op = 'INSERT' then
    who    := coalesce(nullif(new.full_name,''), new.first_name, 'عضوة');
    head   := 'إضافة في شجرة النساء';
    detail := who || case when new.gender = 'female' then ' أُضيفت' else ' أُضيف' end
              || ' إلى شجرة النساء';
    k      := 'women_add';

  else
    -- التعديل: نسجّل الحقول التي تغيّرت فعلاً لا كل حفظ
    who := coalesce(nullif(new.full_name,''), new.first_name, 'عضوة');
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

  return case when tg_op = 'DELETE' then old else new end;
end; $$;

drop trigger if exists trg_women_activity_log on public.women_members;
create trigger trg_women_activity_log
after insert or update or delete on public.women_members
for each row execute function public.log_women_change_to_activity();
