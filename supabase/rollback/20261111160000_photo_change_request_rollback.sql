-- تراجع 20261111160000_photo_change_request — يرجع السيرفر كما كان قبل «طلب تغيير الصورة».
-- ١) الصور التي أخفاها طلب مفتوح (hid_photo) تُظهر أولاً — لا تبقى مخفية بلا طلب يُظهرها.
--    ما أخفاه العضو بنفسه لا يُمسّ.
-- ٢) يحذف المشغّل والدوال الثلاث والجدول بسجلّه (لا رجعة لسجلّ الطلبات).
-- الإشعارات المرسلة (kind = photo_change_request) تبقى في صناديق الأعضاء كنصّ عادي.
-- التطبيقات بعده: الزرّ يعرض «تحتاج تحديث السيرفر»، ولا مربّع للعضو (الجدول غائب = لا طلب).

do $do$
begin
  if to_regclass('public.photo_change_requests') is not null then
    update public.profiles p
       set is_photo_hidden = false
      from public.photo_change_requests r
     where r.member_id = p.id and r.resolved_at is null and r.hid_photo and p.is_photo_hidden;
  end if;
end
$do$;

drop trigger if exists trg_zzzz_photo_change_resolve on public.profiles;
drop function if exists public.trg_photo_change_resolve();
drop function if exists public.cancel_photo_change(uuid);
drop function if exists public.request_photo_change(uuid, text, boolean);
drop table if exists public.photo_change_requests;
