-- «مسجّلون بلا صورة»: أبناء البنات المسجّلون يُنبَّهون مثل غيرهم (بلاغ المالك ٢٠٢٦-١١-٢٧ — «حسين علي محمد الصاغة»).
-- NOT APPLIED — يطبّقه المدير بعد المراجعة. فوق 20261126200000_photo_requests_fixes (مطبَّق ٢٠٢٦-١١-٢٦).
--
-- كانت private.photo_nudge_listed تستبعد ابن البنت (daughter_son_lineage) لأن قائمة التطبيق تُبنى من app_usage_members،
-- وتلك تستبعدهم عمداً (لا يُعدّون في أرقام العائلة). فكان ابن البنت المسجّل بلا صورة لا يظهر في «مسجّلون بلا صورة» ولا
-- يصله «نبّههم كلهم». المالك يريده مثل غيره من الرجال المسجّلين.
--
-- التغيير الوحيد: حذف شرط «ليس ابن بنت». كل شرط آخر كما هو حرفياً: ليس المتصل، حيّ، status = active، ليس pending، المالك
-- للمالك فقط، ليس أنثى، بلا صورة (avatar_url وphoto_url)، له رقم هاتف، له حساب دخول أو جهاز.
-- لا يمسّ: app_usage_members وأرقام العائلة (أبناء البنات خارجها كما هم)، request_photo_change (لم يستثنهم أصلاً)،
-- photo_requests_remind_tick (لم يستثنهم أصلاً)، request_photo_add_all (تقرأ هذه الدالة).
-- التطبيق: نسخة الآيفون بعد هذا البلاغ تعرض ابن البنت في القائمة (قراءة get_members_last_signin الموجودة). قبل الترحيل
-- يمرّ «نبّهه» الفردي له، ويتخطّاه «نبّههم كلهم» فيقول الرقم الذي أُرسل فعلاً.
--
-- الحي يوم الكتابة: ٣ أبناء بنات كلهم لهم حساب، اثنان بلا صورة (يدخلان القاعدة).
-- التراجع: rollback/20261127100000_photo_nudge_daughter_sons_rollback.sql (يرجع نصّ 20261126200000 حرفياً)
-- تجربة: cd supabase/tests/family_links && node photo_requests_fixes.test.mjs

create or replace function private.photo_nudge_listed(p_member uuid, p_me uuid, p_role text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1 from public.profiles p
     where p.id = p_member
       and p.id is distinct from p_me
       and not coalesce(p.is_deceased, false)
       and p.status = 'active'
       and coalesce(p.role, '') <> 'pending'
       and (coalesce(p.role, '') <> 'owner' or p_role = 'owner')
       and lower(coalesce(p.gender, '')) <> 'female'
       and nullif(btrim(coalesce(p.avatar_url, '')), '') is null
       and nullif(btrim(coalesce(p.photo_url, '')), '') is null
       and nullif(btrim(coalesce(p.phone_number, '')), '') is not null
       and (public.profile_has_login(p.id)
            or exists (select 1 from public.device_tokens t where t.member_id = p.id)));
$function$;

revoke all on function private.photo_nudge_listed(uuid, uuid, text) from public, anon, authenticated;
