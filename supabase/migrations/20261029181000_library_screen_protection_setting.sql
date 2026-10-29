-- منع لقطة الشاشة في المكتبة (طلب المالك ٢٠٢٦-١٠-٢٩: «حتى لقطة الشاشة ابيها على الكل»)
insert into public.app_config (key, value, default_value, kind, category, label_ar, help_ar, rules, is_public, sort, max_length)
values ('library_screen_protection', '"all"', '"members"', 'text', 'general', 'منع لقطة الشاشة في المكتبة',
 'all: على الجميع · members: على الأعضاء فقط · off: مطفأ.', '{}', false, 93, 10)
on conflict (key) do update set value = excluded.value;
