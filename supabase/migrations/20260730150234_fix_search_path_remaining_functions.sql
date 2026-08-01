-- مُستخرَجة من سجل الإنتاج (supabase_migrations.schema_migrations)
-- كانت مطبَّقة على القاعدة لكن ملفها مفقود من المستودع.

alter function public.avatar_target_id(text)          set search_path = public;
alter function public.normalize_phone(text)           set search_path = public;
alter function public.phones_match_suffix(text, text) set search_path = public;;
