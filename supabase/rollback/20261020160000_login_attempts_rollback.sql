-- تراجع 20261020160000 («محاولات الدخول»): يحذف الجدول ودواله. السجل (آخر ٣٠ يوماً من الأرقام) يضيع — مقصود،
-- فهو بيانات حساسة بلا نسخة أخرى. لا شيء آخر يعتمد عليه: send-sms-kwtsms تسجّل «بأفضل جهد» فترجع لها أخطاء
-- 404 من log_login_attempt تُبلع ولا تغيّر ردّها؛ أعد نشر النسخة السابقة منها (بلا التسجيل) إن أردت سجلاتها نظيفة.
drop function if exists public.sms_login_attempts(int);
drop function if exists public.log_login_attempt(text, text);
drop function if exists public.login_attempt_profile_id(text);
drop table if exists public.login_attempts;
