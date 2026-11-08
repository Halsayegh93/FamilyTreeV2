-- تراجع 20261107200000_admin_role_matrix: يحذف المفتاح وفحصه. التطبيق يرجع لافتراضه المكتوب (`AdminRoleMatrix.swift`،
-- = المقترح المعتمد) — لا شيء ينكسر.
drop trigger if exists trg_app_config_role_matrix_guard on public.app_config;
delete from public.app_config where key = 'admin_role_matrix';
drop function if exists private.app_config_role_matrix_guard();
drop function if exists private.admin_role_matrix_problem(jsonb);
