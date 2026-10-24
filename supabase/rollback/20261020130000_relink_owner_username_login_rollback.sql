-- تراجع 20261020130000: يرجّع حساب «hasan» في الموقع للإشارة لملف المالك القديم (المحذوف) كما كان
update auth.users
   set raw_app_meta_data = jsonb_set(raw_app_meta_data, '{profile_id}', '"9849ab4f-fc16-495e-b82d-33811d4b8d3c"'::jsonb)
 where id = 'b4e0d4ee-4c6f-4a71-8557-4aca6b751399'
   and raw_app_meta_data->>'profile_id' = '88d7b2f2-aca2-4705-952e-b863def266f8';
