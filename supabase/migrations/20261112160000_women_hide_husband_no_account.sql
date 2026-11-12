-- الزوج يُخفي زوجته أو يُظهرها فقط إذا لم يكن لها حساب (طلب المالك ٢٠٢٦-١١-١٢ «إذا ما عندها حساب زوجها يقدر
-- يخفيها أو يظهرها»)؛ صاحبة الحساب تقرر ظهورها بنفسها من «تعديل الملف الشخصي». يحلّ محل قاعدة «أخفت نفسها».
-- التراجع: supabase/rollback/20261112160000_women_hide_husband_no_account_rollback.sql

create or replace function public.set_self_woman_hidden(p_woman_id uuid, p_hidden boolean)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  me uuid := public.my_active_women_node();
  w public.women_members%rowtype;
begin
  if me is null then
    raise exception 'no_node' using errcode = '42501', hint = 'no_node';
  end if;
  select * into w from public.women_members
   where id = p_woman_id
     and coalesce(lower(gender), 'female') = 'female'
     and (husband_id = me or id = me);
  if not found then
    raise exception 'تقدر تخفي نفسك أو زوجتك فقط' using errcode = '42501', hint = 'not_your_family';
  end if;
  -- زوجته صاحبة حساب: هي تقرر ظهورها من حسابها (الإخفاء والإظهار)
  if w.id <> me and w.linked_user_id is not null then
    raise exception 'لزوجتك حساب — هي تقرر ظهورها من حسابها' using errcode = '42501', hint = 'has_account';
  end if;
  perform set_config('family.self_hide', 'on', true);
  update public.women_members
     set is_hidden_from_tree = coalesce(p_hidden, false)
   where id = p_woman_id;
  perform set_config('family.self_hide', 'off', true);
end;
$function$;

revoke all on function public.set_self_woman_hidden(uuid, boolean) from public, anon;
grant execute on function public.set_self_woman_hidden(uuid, boolean) to authenticated;

create or replace function public.set_self_wife_hidden(p_wife_id uuid, p_hidden boolean)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  me uuid := public.my_active_women_node();
  w public.women_members%rowtype;
begin
  if me is null then raise exception 'no_node'; end if;
  select * into w from public.women_members where id = p_wife_id and husband_id = me;
  if not found then raise exception 'not_your_wife'; end if;
  if w.linked_user_id is not null then
    raise exception 'لزوجتك حساب — هي تقرر ظهورها من حسابها' using errcode = '42501', hint = 'has_account';
  end if;
  perform set_config('family.self_hide', 'on', true);
  update public.women_members
     set is_hidden_from_tree = coalesce(p_hidden, false)
   where id = p_wife_id;
  perform set_config('family.self_hide', 'off', true);
end; $function$;
