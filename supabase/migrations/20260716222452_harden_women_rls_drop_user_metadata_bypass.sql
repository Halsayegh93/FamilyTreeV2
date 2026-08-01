-- مُستخرَجة من سجل الإنتاج (supabase_migrations.schema_migrations)
-- كانت مطبَّقة على القاعدة لكن ملفها مفقود من المستودع.

-- SECURITY FIX: remove the user-editable auth.jwt()->'user_metadata'->>'profile_id'
-- bypass from women/external/web RLS. Role is now resolved ONLY from
-- profiles.id = auth.uid() (identical to the secure is_moderator() pattern),
-- so a member can no longer set their own metadata to impersonate an admin.
-- Role arrays are preserved exactly (no behavior change for legitimate mods).

ALTER POLICY women_members_write ON public.women_members
  USING      (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role = ANY (ARRAY['owner','admin','monitor'])))
  WITH CHECK (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role = ANY (ARRAY['owner','admin','monitor'])));

ALTER POLICY external_spouses_select_mods ON public.external_spouses
  USING      (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role = ANY (ARRAY['owner','admin','monitor','supervisor'])));

ALTER POLICY external_spouses_write_mods ON public.external_spouses
  USING      (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role = ANY (ARRAY['owner','admin','monitor','supervisor'])))
  WITH CHECK (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role = ANY (ARRAY['owner','admin','monitor','supervisor'])));

ALTER POLICY web_relatives_select ON public.web_relatives
  USING      (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role = ANY (ARRAY['owner','admin','monitor','supervisor'])));

ALTER POLICY web_relatives_write ON public.web_relatives
  USING      (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role = ANY (ARRAY['owner','admin','monitor'])))
  WITH CHECK (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role = ANY (ARRAY['owner','admin','monitor'])));;
