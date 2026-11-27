-- مطبَّق على الحي ٢٠٢٦-١١-٢٧ بعد تجربة begin…rollback (عن غيره: مرفوض · عن نفسه: يمر · تعديل اسم غيره: يمر)
-- «تغيير الرقم» عن نفسه فقط (قرار المالك ٢٠٢٦-١١-٢٧: «رقمه فقط»).
-- الثغرة: طلب «تعديل الشجرة» بإجراء edit_phone كان مسموحاً عن أي عضو؛ إن وافقت الإدارة يسجّل الطالب بالرقم ويأخذ السجل.
-- الإدارة لا تتأثر (تخرج من الحارس قبل هذا الفحص)، و«phone_change» عن النفس كما كان.
-- التراجع: أعد الدالة بحذف الفحص المضاف (replace المعاكس).
do $mig$
declare d text := pg_get_functiondef('public.guard_admin_request_insert()'::regprocedure); n text;
begin
  n := replace(d, $x$    -- «طلب آخر» يأتي فقط من تعديل العضو لملفه بعد تجاوز الحد.$x$,
$x$    -- تغيير الرقم عن نفسه فقط (20261127220000)
    if act = 'edit_phone' and new.member_id <> new.requester_id then
      raise exception 'admin_request_phone_not_self' using errcode = '42501';
    end if;

    -- «طلب آخر» يأتي فقط من تعديل العضو لملفه بعد تجاوز الحد.$x$);
  if n = d then raise exception 'guard_admin_request_insert: النص المتوقع غير موجود'; end if;
  execute n;
end $mig$;
