-- تراجع 20261020151000 (يُشغَّل قبل تراجع 20261020150000): يحذف قراءة الإدارة ودوال kwtsms-admin.
-- لا بيانات تضيع (الدوال فقط). بعده الدالة الطرفية kwtsms-admin ترجع «storage_unavailable» لإجراءاتها التي تحفظ
-- (الرصيد يظهر بدون حفظ، «اختبار إرسال لرقمي» يرفض قبل أي إرسال) — احذفها أو أوقفها معه.
drop function if exists public.sms_admin_overview();
drop function if exists public.reserve_kwtsms_admin_test(text, text, boolean);
drop function if exists public.record_kwtsms_delivery_status(text, text);
drop function if exists public.record_kwtsms_balance(numeric);
