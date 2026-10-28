-- «عائلتي»: الأم أو الزوجة من بنات الشجرة (طلب المالك ٢٠٢٦-١٠-٢٤ «عند الاختيار وغير موجودة بالشجرة ونبي نضيفها لاب
-- بالشجرة … ان اب الام او الزوجة موجود بالشجرة»).
-- add_or_link_self_relative(p_kind 'wife'|'mother'|'sister', p_father_id, p_woman_id?, p_name?) → معرّف المرأة
--   • العضو المفعّل فقط، وعن نفسه فقط (عقدته في شجرة النساء)
--   • p_woman_id = بنت موجودة لـ p_father_id تُربط، وإلا p_name = بنت جديدة تُضاف تحت أبيها (الاسم + سلسلة الأب)
--   • زوجة: البنت بلا زوج (أو زوجها هو المتصل) ← husband_id = المتصل
--   • أم: البنت بلا زوج (أو زوجها أبو المتصل) ← زوجة أبيه + mother_id للمتصل
--   • أخت (طلب المالك «شلون ممكن يضيفهم الاخو في شجرة النساء»): بنت جديدة تحت أبي المتصل نفسه فقط
--     (p_father_id = أبوه، بالاسم — الموجودة أصلاً أخته فلا ربط)
-- إشعار الإدارة يصل من مشغّل شجرة النساء نفسه (log_women_change_to_activity: «أُضيفت بنت»/تعديل الزوج)،
-- وكل تغيير رابط يُسجَّل في family_link_history.
-- أخطاؤها بـ hint: not_allowed · bad_kind · no_father · no_own_father · not_daughter · already_married · name_required
-- التراجع: rollback/20261024181150_add_or_link_self_relative_rollback.sql
-- تجربة: cd supabase/tests/family_links && node add_or_link_self_relative.test.mjs

create or replace function public.add_or_link_self_relative(
  p_kind text, p_father_id uuid, p_woman_id uuid default null, p_name text default null)
 returns uuid
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  me        uuid;
  k         text := lower(btrim(coalesce(p_kind, '')));
  nm        text := btrim(coalesce(p_name, ''));
  f         public.women_members%rowtype;
  w         public.women_members%rowtype;
  my_father uuid;
  wid       uuid;
begin
  -- المتصل: مفعّل فقط (المعلّق والمجمّد لا)
  if coalesce(public.current_user_role(), '') not in ('member', 'supervisor', 'monitor', 'admin', 'owner') then
    raise exception 'حسابك غير مفعّل' using errcode = '42501', hint = 'not_allowed';
  end if;
  me := public.my_women_node();
  if me is null then
    raise exception 'لا توجد لك عقدة في الشجرة بعد' using errcode = 'P0001', hint = 'no_node';
  end if;
  if k not in ('wife', 'mother', 'sister') then
    raise exception 'نوع غير معروف' using errcode = '22023', hint = 'bad_kind';
  end if;

  -- الأب: رجل في الشجرة (نسخته في شجرة النساء بنفس المعرّف)، وليس المتصل نفسه
  select * into f from public.women_members where id = p_father_id;
  if not found or lower(coalesce(f.gender, 'male')) <> 'male' or f.id = me then
    raise exception 'الأب غير موجود في الشجرة' using errcode = 'P0001', hint = 'no_father';
  end if;

  if k in ('mother', 'sister') then
    select parent_id into my_father from public.women_members where id = me;
    if my_father is null then
      raise exception 'أبوك غير مسجّل في الشجرة — اطلب ربطك من الإدارة' using errcode = 'P0001', hint = 'no_own_father';
    end if;
  end if;
  -- الأخت تحت أبيه هو فقط، وبالاسم
  if k = 'sister' and (p_father_id is distinct from my_father or p_woman_id is not null) then
    raise exception 'الأخت تُضاف تحت أبيك أنت بالاسم' using errcode = 'P0001', hint = 'not_daughter';
  end if;

  if p_woman_id is not null then
    select * into w from public.women_members where id = p_woman_id for update;
    if not found or w.parent_id is distinct from p_father_id or lower(coalesce(w.gender, '')) <> 'female' or w.id = me then
      raise exception 'هذه ليست من بنات الأب المختار' using errcode = 'P0001', hint = 'not_daughter';
    end if;
    if (k = 'wife' and w.husband_id is not null and w.husband_id <> me)
       or (k = 'mother' and w.husband_id is not null and w.husband_id <> my_father) then
      raise exception 'مرتبطة بزوج آخر — راجع الإدارة' using errcode = 'P0001', hint = 'already_married';
    end if;
    wid := w.id;
  else
    if nm = '' then
      raise exception 'اكتب الاسم' using errcode = '22023', hint = 'name_required';
    end if;
    insert into public.women_members (id, first_name, full_name, parent_id, gender, sort_order)
    values (gen_random_uuid(), nm,
            btrim(nm || ' ' || coalesce(nullif(btrim(f.full_name), ''), btrim(coalesce(f.first_name, '')))),
            p_father_id, 'female',
            coalesce((select max(c.sort_order) + 1 from public.women_members c where c.parent_id = p_father_id), 0))
    returning id into wid;
  end if;

  if k = 'sister' then
    null;  -- بنت جديدة تحت أبيه — لا ربط زوج ولا أم
  elsif k = 'wife' then
    update public.women_members set husband_id = me, is_married = true where id = wid;
  else
    update public.women_members set husband_id = coalesce(husband_id, my_father), is_married = true where id = wid;
    update public.women_members set mother_id = wid where id = me;
  end if;

  return wid;
end;
$function$;

comment on function public.add_or_link_self_relative(text, uuid, uuid, text) is
  'الأم/الزوجة من بنات الشجرة: ربط بنت موجودة لأب في الشجرة أو إضافتها تحته — للعضو المفعّل عن نفسه؛ hint: not_allowed | no_node | bad_kind | no_father | no_own_father | not_daughter | already_married | name_required';

revoke all on function public.add_or_link_self_relative(text, uuid, uuid, text) from public, anon;
grant execute on function public.add_or_link_self_relative(text, uuid, uuid, text) to authenticated;
