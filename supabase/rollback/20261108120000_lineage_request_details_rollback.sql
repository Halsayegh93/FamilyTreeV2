-- تراجع 20261108120000_lineage_request_details — دالة قراءة فقط، لا بيانات تُمسّ.
-- التطبيقات ترجع لبطاقة «طلب نسب» كما كانت (الأم والأب من حمولة الطلب).
drop function if exists public.lineage_request_details(uuid);
