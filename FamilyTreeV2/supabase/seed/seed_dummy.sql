-- Dummy data for local/dev testing
-- NOTE: Replace UUIDs if they conflict in your project.

insert into public.profiles (id, full_name, first_name, phone_number, birth_date, role, status, is_deceased, father_id, sort_order)
values
('00000000-0000-0000-0000-000000000001', 'محمد سالم عبدالله السالم', 'محمد', '90000001', '1955-02-01', 'admin', 'active', false, null, 0),
('00000000-0000-0000-0000-000000000002', 'أحمد محمد سالم السالم', 'أحمد', '90000002', '1980-04-10', 'supervisor', 'active', false, '00000000-0000-0000-0000-000000000001', 0),
('00000000-0000-0000-0000-000000000003', 'خالد محمد سالم السالم', 'خالد', '90000003', '1984-09-21', 'member', 'active', false, '00000000-0000-0000-0000-000000000001', 1),
('00000000-0000-0000-0000-000000000004', 'عبدالله أحمد محمد السالم', 'عبدالله', '90000004', '2007-01-15', 'member', 'active', false, '00000000-0000-0000-0000-000000000002', 0),
('00000000-0000-0000-0000-000000000005', 'يوسف خالد محمد السالم', 'يوسف', '90000005', '2010-06-18', 'pending', 'pending', false, '00000000-0000-0000-0000-000000000003', 0)
on conflict (id) do nothing;

insert into public.news (id, author_id, author_name, author_role, role_color, content, type, approval_status, created_at)
values
('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'محمد سالم عبدالله السالم', 'مدير', 'purple', 'تم إطلاق النسخة التجريبية لتطبيق العائلة.', 'تنبيه', 'approved', now() - interval '2 day'),
('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000003', 'خالد محمد سالم السالم', 'عضو', 'blue', 'اقتراح لقاء عائلي يوم الجمعة القادمة.', 'تصويت', 'pending', now() - interval '3 hour')
on conflict (id) do nothing;

insert into public.admin_requests (id, member_id, requester_id, request_type, status, details, created_at)
values
('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000005', 'join_request', 'pending', 'طلب انضمام جديد بانتظار الموافقة والربط بالأب.', now() - interval '1 hour')
on conflict (id) do nothing;
