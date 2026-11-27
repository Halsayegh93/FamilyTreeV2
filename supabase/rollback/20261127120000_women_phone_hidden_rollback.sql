-- تراجع 20261127120000_women_phone_hidden: يحذف المشغّل ودالته. العلم is_phone_hidden يبقى كما هو على الصفوف
-- (من أُخفيت تبقى مخفية — أظهرها بيدك إن لزم).
drop trigger if exists trg_women_phone_hidden on public.profiles;
drop function if exists private.women_phone_hidden();
