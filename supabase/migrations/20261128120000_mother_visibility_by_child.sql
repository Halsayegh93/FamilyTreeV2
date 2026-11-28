-- مطبَّق على الحي ٢٠٢٦-١١-٢٨ بعد تجربة begin…rollback (حسين يطفئ ظهور الوالد: false/true، ثم تراجع)
-- قرار المالك ٢٠٢٦-١١-٢٨: ابن البنت / بنت البنت صاحب الحساب، وأمّه بلا حساب، يختار من «حسابي ← الخصوصية»
-- «ظهور الوالد بجانب الوالدة» (spouse_shown) و«ظهور الأبناء تحت الوالدة» (children_shown) على عقدة أمّه.
-- إن كان لأمّه حساب فهي تقرّر (women_family_set_visibility) — يُرفض بـ hint = mother_has_account.
-- يغيّر هذين العمودين فقط على الأم، ولا شيء غيرهما. null = بلا تغيير.
-- أخطاؤه بـ hint: not_allowed (غير مفعّل/مجمّد) · no_node (بلا عقدة) · no_mother (بلا أمّ) · mother_has_account.
-- التراجع: supabase/rollback/20261128120000_mother_visibility_by_child_rollback.sql
create or replace function public.set_mother_visibility(
  p_spouse boolean default null, p_children boolean default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_me     uuid := public.current_profile_id();
  v_mother uuid;
  m        public.women_members%rowtype;
begin
  if v_me is null or coalesce(public.current_user_role(), '') not in ('member', 'supervisor', 'monitor', 'admin', 'owner') then
    raise exception 'الحساب غير مفعّل' using errcode = '42501', hint = 'not_allowed';
  end if;

  select w.mother_id into v_mother
    from public.women_members w
   where w.id = v_me or w.linked_user_id = v_me or w.linked_user_id = auth.uid()
   order by (w.id = v_me) desc
   limit 1;
  if not found then
    raise exception 'لا توجد لك عقدة في شجرة النساء' using errcode = 'P0001', hint = 'no_node';
  end if;
  if v_mother is null then
    raise exception 'الوالدة غير مسجّلة في الشجرة' using errcode = 'P0001', hint = 'no_mother';
  end if;

  select * into m from public.women_members where id = v_mother for update;
  if not found then
    raise exception 'الوالدة غير مسجّلة في الشجرة' using errcode = 'P0001', hint = 'no_mother';
  end if;
  if m.linked_user_id is not null then
    raise exception 'للوالدة حساب في التطبيق، والاختيار لها' using errcode = '42501', hint = 'mother_has_account';
  end if;

  if p_spouse is not null or p_children is not null then
    update public.women_members
       set spouse_shown   = coalesce(p_spouse, spouse_shown),
           children_shown = coalesce(p_children, children_shown)
     where id = v_mother
    returning * into m;
  end if;

  return jsonb_build_object('mother_id', m.id,
                            'spouse', coalesce(m.spouse_shown, false),
                            'children', coalesce(m.children_shown, false));
end
$function$;

revoke all on function public.set_mother_visibility(boolean, boolean) from public, anon;
grant execute on function public.set_mother_visibility(boolean, boolean) to authenticated;
