-- استرجاع أرقام الخمسة اللي انشالت يوم ٢٠٢٦-١١-٠٩ بأمر المالك («احذفهم … كارقام هواتف، خل اساميهم والصور»)
-- عندهم رقم في الشجرة وما فتحوا التطبيق أبداً (بلا حساب دخول ولا جهاز). شغّله فقط لو المالك طلب الرجوع.
update public.profiles set phone_number = '+96565070809' where id = '51b71f71-d6e7-44bb-b35e-2ed167b9446f';
update public.profiles set phone_number = '+96599053775' where id = '85c0c315-39ba-443a-8f28-39283352806e';
update public.profiles set phone_number = '+96590030086' where id = '965a0006-a270-4022-8ac5-803b886ebf7a';
update public.profiles set phone_number = '+96597664191' where id = 'ad44ea1e-ce88-401f-b8d3-edca765ca2d4';
update public.profiles set phone_number = '+96590020062' where id = 'f22c0fb4-9589-4594-9f0f-6899782779cc';

-- اسم حساب مراجعة أبل قبل تغييره يوم ٢٠٢٦-١١-٠٩ (أمر المالك: «حساب المراجعة»)
update public.profiles set first_name = 'Test', full_name = 'Test الصايغ' where id = 'f20a2fd2-67e2-44ae-a336-9f12e12bd13c';
