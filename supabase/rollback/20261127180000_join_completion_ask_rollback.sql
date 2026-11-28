-- تراجع 20261127180000_join_completion_ask — يحذف الدوال الأربع والجدول (طلبات الاستكمال المفتوحة تُحذف معه؛
-- الطلبات نفسها والإشعارات المرسلة تبقى كما هي).
drop function if exists public.answer_completion_ask(jsonb);
drop function if exists public.my_completion_ask();
drop function if exists public.ask_join_completion(uuid, text[], text);
drop function if exists public.join_completion_field_label(text);
drop table if exists public.join_completion_asks;
