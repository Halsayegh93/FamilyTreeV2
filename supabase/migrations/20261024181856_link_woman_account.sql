-- دخول النساء للتطبيق (طلب المالك ٢٠٢٦-١٠-٢٤ «ابدأ بدخول النساء للتطبيق»)
-- المرأة تسجّل برقمها كأي عضو (ملف في profiles للدخول والأجهزة والإشعارات والدور)، وتختار «أنثى» في التسجيل.
-- طلب انضمامها يُربط بعقدتها في شجرة النساء بدل «ربط بالشجرة» (merge_member_into_tree لملفات الرجال فقط):
-- link_woman_account(p_request_id, p_woman_id?, p_father_id?, p_name?) → معرّف عقدتها
--   • للمالك/المدير/المراقب (مجال الشجرة)، والطلب انضمام/ربط معلّق لملف أنثى
--   • p_woman_id = عقدة أنثى موجودة بلا حساب تُربط، وإلا عقدة جديدة باسم p_name تحت أبيها p_father_id
--   • الملف: عضو مفعّل، مخفي من شجرة الرجال (مكانها شجرة النساء)، رقمها مخفي افتراضياً، الاسم من عقدتها
--   • women_members.linked_user_id = ملفها (my_women_node يجدها بها) · الطلب يُغلق «مقبول» · إشعار «مرحباً بك»
-- أخطاؤها بـ hint: not_allowed · request_not_found · already_handled · not_female · has_father · node_taken ·
--   not_female_node · no_father · name_required
-- التراجع: rollback/20261024181856_link_woman_account_rollback.sql
-- تجربة: cd supabase/tests/family_links && node link_woman_account.test.mjs

create or replace function public.link_woman_account(
  p_request_id uuid, p_woman_id uuid default null, p_father_id uuid default null, p_name text default null)
 returns uuid
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  me     uuid := public.current_profile_id();
  r      public.admin_requests%rowtype;
  p      public.profiles%rowtype;
  w      public.women_members%rowtype;
  f      public.women_members%rowtype;
  nm     text := btrim(coalesce(p_name, ''));
  wid    uuid;
begin
  if coalesce(public.current_user_role(), '') not in ('owner', 'admin', 'monitor') then
    raise exception 'ربط النساء للمالك والمدير والمراقب' using errcode = '42501', hint = 'not_allowed';
  end if;

  select * into r from public.admin_requests where id = p_request_id for update;
  if not found or r.request_type not in ('join_request', 'link_request') then
    raise exception 'الطلب غير موجود' using errcode = 'P0001', hint = 'request_not_found';
  end if;
  if r.status is distinct from 'pending' then
    raise exception 'الطلب عولج من قبل' using errcode = 'P0001', hint = 'already_handled';
  end if;

  select * into p from public.profiles where id = r.member_id for update;
  if not found or lower(coalesce(p.gender, '')) <> 'female' then
    raise exception 'صاحب الطلب ليس أنثى' using errcode = 'P0001', hint = 'not_female';
  end if;
  -- ملف حساب فقط — لا أب ولا أبناء في شجرة الرجال
  if p.father_id is not null or exists (select 1 from public.profiles c where c.father_id = p.id) then
    raise exception 'الملف مرتبط بشجرة الرجال — صحّحه أولاً' using errcode = 'P0001', hint = 'has_father';
  end if;

  if p_woman_id is not null then
    select * into w from public.women_members where id = p_woman_id for update;
    if not found or lower(coalesce(w.gender, '')) <> 'female' then
      raise exception 'العقدة ليست أنثى في شجرة النساء' using errcode = 'P0001', hint = 'not_female_node';
    end if;
    if w.linked_user_id is not null and w.linked_user_id <> p.id then
      raise exception 'العقدة مربوطة بحساب آخر' using errcode = 'P0001', hint = 'node_taken';
    end if;
    wid := w.id;
  else
    if nm = '' then
      raise exception 'اكتب الاسم' using errcode = '22023', hint = 'name_required';
    end if;
    select * into f from public.women_members where id = p_father_id;
    if not found or lower(coalesce(f.gender, 'male')) <> 'male' then
      raise exception 'الأب غير موجود في الشجرة' using errcode = 'P0001', hint = 'no_father';
    end if;
    insert into public.women_members (id, first_name, full_name, parent_id, gender, sort_order)
    values (gen_random_uuid(), nm,
            btrim(nm || ' ' || coalesce(nullif(btrim(f.full_name), ''), btrim(coalesce(f.first_name, '')))),
            p_father_id, 'female',
            coalesce((select max(c.sort_order) + 1 from public.women_members c where c.parent_id = p_father_id), 0))
    returning * into w;
    wid := w.id;
  end if;

  -- حساب واحد لكل عقدة، وعقدة واحدة لكل حساب
  update public.women_members set linked_user_id = null where linked_user_id = p.id and id <> wid;
  update public.women_members set linked_user_id = p.id where id = wid;

  update public.profiles
     set role = case when role = 'pending' then 'member' else role end,
         status = 'active',
         is_hidden_from_tree = true,
         is_phone_hidden = true,
         first_name = coalesce(nullif(btrim(w.first_name), ''), first_name),
         full_name = coalesce(nullif(btrim(w.full_name), ''), full_name)
   where id = p.id;

  update public.admin_requests
     set status = 'approved', replied_by = me, replied_at = now()
   where id = r.id;

  insert into public.notifications (target_member_id, title, body, kind, created_by)
  values (p.id, 'مرحباً بك في العائلة', 'تم قبول طلب انضمامك وربطك بشجرة النساء', 'join_approved', me);

  return wid;
end;
$function$;

comment on function public.link_woman_account(uuid, uuid, uuid, text) is
  'دخول النساء: ربط طلب انضمام أنثى بعقدتها في شجرة النساء (أو عقدة جديدة تحت أبيها) وتفعيل حسابها — للمالك/المدير/المراقب؛ hint: not_allowed | request_not_found | already_handled | not_female | has_father | node_taken | not_female_node | no_father | name_required';

revoke all on function public.link_woman_account(uuid, uuid, uuid, text) from public, anon;
grant execute on function public.link_woman_account(uuid, uuid, uuid, text) to authenticated;
