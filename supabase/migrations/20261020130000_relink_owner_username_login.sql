-- طلب المالك ٢٠٢٦-١٠-٢٠ («في اسم مستخدم في الموقع ليش مو مربوط فيني» ثم «نعم اربط»):
-- حساب الدخول باسم المستخدم «hasan» في الموقع (hasan@familytree.local) كان يشير لملف المالك القديم 9849ab4f
-- اللي انحذف عند نقل الملف إلى 88d7b2f2 (٢٠٢٦-٠٩-٢٤) — فصار الدخول به بلا ملف. نربطه بملف المالك الحالي.
-- التراجع: supabase/rollback/20261020130000_relink_owner_username_login_rollback.sql
update auth.users
   set raw_app_meta_data = jsonb_set(coalesce(raw_app_meta_data, '{}'::jsonb), '{profile_id}',
                                     '"88d7b2f2-aca2-4705-952e-b863def266f8"'::jsonb)
 where id = 'b4e0d4ee-4c6f-4a71-8557-4aca6b751399'
   and email = 'hasan@familytree.local'
   and raw_app_meta_data->>'profile_id' = '9849ab4f-fc16-495e-b82d-33811d4b8d3c';
