-- مُستخرَجة من سجل الإنتاج (supabase_migrations.schema_migrations)
-- كانت مطبَّقة على القاعدة لكن ملفها مفقود من المستودع.

-- SECURITY: pin search_path on every SECURITY DEFINER function that lacks it,
-- to prevent search_path-injection (a user creating a shadow object on the path
-- could hijack an elevated-privilege function). Includes the critical
-- prevent_role_self_promotion trigger. Signature-safe via format().
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid, p.proname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef
      AND NOT (p.proconfig IS NOT NULL
               AND EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%'))
  LOOP
    EXECUTE format('ALTER FUNCTION public.%I(%s) SET search_path = public, extensions', r.proname, r.args);
    RAISE NOTICE 'pinned search_path on %(%)', r.proname, r.args;
  END LOOP;
END $$;;
