-- مطبَّق على الحي ٢٠٢٦-١١-٢٧ بعد تجربة begin…rollback
-- صورة زوج البنت من خارج العائلة بلا حساب (موافقة المالك ٢٠٢٦-١١-٢٧).
-- كان «إضافة صورة» (tree_edit add_photo من زوجته أو ابنه) يظهر فقط حين له حساب، لأن الموافقة تكتب profiles.avatar_url
-- و admin_requests.member_id مفتاح أجنبي على profiles. الآن لعقدته في شجرة النساء وحدها:
--   • الطلب: member_id = مقدّم الطلب نفسه (ملف موجود)، و details.targetMemberId = عقدة الزوج في women_members.
--     حارس الإدراج (guard_admin_request_insert) يقبل هذا الفرق فقط حين private.outside_husband_photo_ok:
--     الإجراء add_photo، member_id = مقدّم الطلب، العقدة ذكر من خارج العائلة (is_outside_family) بلا ملف في profiles
--     وغير مربوطة بحساب، ومقدّم الطلب زوجته (husband_id) أو ابنه/ابنته (parent_id) في شجرة النساء.
--     والاسم المعروض (targetMemberName) من العقدة لا من ملف مقدّم الطلب. فحص رابط الصورة كما هو.
--   • الموافقة (private.decide_admin_request_core): المستهدف في profiles → كما كان حرفياً؛ وإلا عقدة شجرة النساء
--     الذكر فقط ← women_members.avatar_url و photo_url. الأنثى لا صورة لها أبداً (غير الذكر = bad_payload،
--     والمشغّل الحي no_photo_for_females يفرّغها أصلاً). العمودان موجودان في women_members.
-- الترقيع نصّي على الحي (pg_get_functiondef + replace) مثل 20261127220000 — يفشل إن تغيّر النص المتوقع.
-- التراجع: supabase/rollback/20261127260000_outside_husband_photo_rollback.sql
-- تجربة: cd supabase/tests/family_links && node outside_husband_photo.test.mjs

create or replace function private.outside_husband_photo_ok(p_act text, p_target text, p_member uuid, p_requester uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce(p_act, '') = 'add_photo'
     and p_member is not null and p_member = p_requester
     and coalesce(p_target, '') ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
     and exists (
       select 1 from public.women_members h
        where h.id = p_target::uuid
          and lower(coalesce(h.gender, '')) = 'male'
          and coalesce(h.is_outside_family, false)
          and h.linked_user_id is null
          and not exists (select 1 from public.profiles p where p.id = h.id)
          and exists (select 1 from public.women_members m
                       where (m.id = p_requester or m.linked_user_id = p_requester)
                         and (m.husband_id = h.id or m.parent_id = h.id)));
$function$;
revoke all on function private.outside_husband_photo_ok(text, text, uuid, uuid) from public, anon, authenticated;

-- ─── ١) حارس الإدراج ───
do $mig$
declare d text := pg_get_functiondef('public.guard_admin_request_insert()'::regprocedure); n text;
begin
  n := replace(d, $x$    if (tgt is not null and (tgt !~ uuid_re or tgt::uuid <> new.member_id))$x$,
$x$    -- صورة زوج البنت من خارج العائلة بلا حساب: المستهدف عقدته في شجرة النساء (20261127260000)
    if (tgt is not null and (tgt !~ uuid_re or (tgt::uuid <> new.member_id
                                                and not private.outside_husband_photo_ok(act, tgt, new.member_id, new.requester_id))))$x$);
  if n = d then raise exception 'guard_admin_request_insert: نص المستهدف المتوقع غير موجود'; end if;
  d := n;
  n := replace(d, $x$    select p.full_name into member_name from public.profiles p where p.id = new.member_id;$x$,
$x$    select p.full_name into member_name from public.profiles p where p.id = new.member_id;
    -- المستهدف عقدة في شجرة النساء (20261127260000): الاسم منها
    if tgt is not null and tgt::uuid <> new.member_id then
      select w.full_name into member_name from public.women_members w where w.id = tgt::uuid;
    end if;$x$);
  if n = d then raise exception 'guard_admin_request_insert: نص الاسم المتوقع غير موجود'; end if;
  execute n;
end $mig$;

-- ─── ٢) الموافقة ───
do $mig$
declare d text := pg_get_functiondef('private.decide_admin_request_core(uuid,text,text,jsonb)'::regprocedure); n text;
begin
  n := replace(d, $x$          update public.profiles set avatar_url = v_text where id = tgt;$x$,
$x$          if exists (select 1 from public.profiles x where x.id = tgt) then
            update public.profiles set avatar_url = v_text where id = tgt;
          else
            -- زوج البنت من خارج العائلة بلا حساب (20261127260000): عقدته في شجرة النساء — للذكر فقط
            update public.women_members set avatar_url = v_text, photo_url = v_text
             where id = tgt and lower(coalesce(gender, '')) = 'male';
            if not found then
              raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload', detail = 'targetMemberId';
            end if;
          end if;$x$);
  if n = d then raise exception 'decide_admin_request_core: نص الصورة المتوقع غير موجود'; end if;
  execute n;
end $mig$;
