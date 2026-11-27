-- تراجع 20261127260000_outside_husband_photo — يعيد نصّي الحارس والموافقة كما كانا حرفياً ويحذف الدالة المساعدة.
-- الصور التي اعتُمدت لعقد شجرة النساء تبقى (women_members.avatar_url/photo_url).

do $mig$
declare d text := pg_get_functiondef('public.guard_admin_request_insert()'::regprocedure); n text;
begin
  n := replace(d, $x$    -- صورة زوج البنت من خارج العائلة بلا حساب: المستهدف عقدته في شجرة النساء (20261127260000)
    if (tgt is not null and (tgt !~ uuid_re or (tgt::uuid <> new.member_id
                                                and not private.outside_husband_photo_ok(act, tgt, new.member_id, new.requester_id))))$x$,
$x$    if (tgt is not null and (tgt !~ uuid_re or tgt::uuid <> new.member_id))$x$);
  if n = d then raise exception 'guard_admin_request_insert: نص المستهدف المرقّع غير موجود'; end if;
  d := n;
  n := replace(d, $x$
    -- المستهدف عقدة في شجرة النساء (20261127260000): الاسم منها
    if tgt is not null and tgt::uuid <> new.member_id then
      select w.full_name into member_name from public.women_members w where w.id = tgt::uuid;
    end if;$x$, '');
  if n = d then raise exception 'guard_admin_request_insert: نص الاسم المرقّع غير موجود'; end if;
  execute n;
end $mig$;

do $mig$
declare d text := pg_get_functiondef('private.decide_admin_request_core(uuid,text,text,jsonb)'::regprocedure); n text;
begin
  n := replace(d, $x$          if exists (select 1 from public.profiles x where x.id = tgt) then
            update public.profiles set avatar_url = v_text where id = tgt;
          else
            -- زوج البنت من خارج العائلة بلا حساب (20261127260000): عقدته في شجرة النساء — للذكر فقط
            update public.women_members set avatar_url = v_text, photo_url = v_text
             where id = tgt and lower(coalesce(gender, '')) = 'male';
            if not found then
              raise exception 'bad_payload' using errcode = '22023', hint = 'bad_payload', detail = 'targetMemberId';
            end if;
          end if;$x$,
$x$          update public.profiles set avatar_url = v_text where id = tgt;$x$);
  if n = d then raise exception 'decide_admin_request_core: نص الصورة المرقّع غير موجود'; end if;
  execute n;
end $mig$;

drop function if exists private.outside_husband_photo_ok(text, text, uuid, uuid);
