-- إلغاء «اعرض الرمز» (قرار المالك ٢٠٢٦-١٠-٢٩ «نعم اصلح»): لا أحد يرى رمز دخول عضو، ولا يُحفظ الرمز أبداً.
-- سجل محاولات الدخول (login_attempts، المُفصح عنه في سياسة الخصوصية) باقٍ كما هو.
-- • store_login_code صار لا يفعل شيئاً (الخطّاف القديم إن رجع لا يحفظ ولا يفشل)، والخطّاف الجديد (send-sms-kwtsms v26) لا يناديه.
-- • الرموز المحفوظة تُمسح (الحالية + السجل)، ودوال عرضها للمالك تُحذف.
-- • سجل مشاهدات الرموز (private.login_code_views، بلا رموز) يبقى للتدقيق ويُمسح مع مدة الحفظ.

create or replace function public.store_login_code(p_phone text, p_code text)
 returns void language plpgsql security definer set search_path to ''
as $function$
begin
  -- متوقّفة عمداً (20261029110000): رمز الدخول لا يُحفظ
  return;
end;
$function$;
revoke all on function public.store_login_code(text, text) from public, anon, authenticated;
grant execute on function public.store_login_code(text, text) to service_role;

drop function if exists public.owner_reveal_login_code(text);
drop function if exists public.owner_number_login_codes(text, integer);
drop function if exists public.owner_login_codes(integer);

delete from private.login_codes;
delete from private.login_code_history;
