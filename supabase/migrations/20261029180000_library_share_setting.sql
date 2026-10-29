-- زر الحفظ والمشاركة في المكتبة (طلب المالك ٢٠٢٦-١٠-٢٩: مخفي عن الإدارة والأعضاء)
insert into public.app_config (key, value, default_value, kind, category, label_ar, help_ar, rules, is_public, sort, max_length)
values ('library_share', '"none"', '"admins"', 'text', 'general', 'زر الحفظ والمشاركة في المكتبة',
 'none: مخفي عن الجميع · admins: للمالك والمدير فقط · all: للجميع.', '{}', false, 92, 10)
on conflict (key) do update set value = excluded.value;
