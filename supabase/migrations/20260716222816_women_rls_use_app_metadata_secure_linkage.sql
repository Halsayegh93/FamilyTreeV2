-- مُستخرَجة من سجل الإنتاج (supabase_migrations.schema_migrations)
-- كانت مطبَّقة على القاعدة لكن ملفها مفقود من المستودع.

-- Restore the profile-indirection needed by username/password admins, but from the
-- SECURE, service-role-only app_metadata claim (NOT the user-editable user_metadata).
-- Users cannot forge app_metadata, so this closes the escalation while keeping access.

ALTER POLICY women_members_write ON public.women_members
  USING      (EXISTS (SELECT 1 FROM public.profiles p WHERE (p.id = auth.uid() OR p.id = NULLIF(auth.jwt()->'app_metadata'->>'profile_id','')::uuid) AND p.role = ANY (ARRAY['owner','admin','monitor'])))
  WITH CHECK (EXISTS (SELECT 1 FROM public.profiles p WHERE (p.id = auth.uid() OR p.id = NULLIF(auth.jwt()->'app_metadata'->>'profile_id','')::uuid) AND p.role = ANY (ARRAY['owner','admin','monitor'])));

ALTER POLICY external_spouses_select_mods ON public.external_spouses
  USING      (EXISTS (SELECT 1 FROM public.profiles p WHERE (p.id = auth.uid() OR p.id = NULLIF(auth.jwt()->'app_metadata'->>'profile_id','')::uuid) AND p.role = ANY (ARRAY['owner','admin','monitor','supervisor'])));

ALTER POLICY external_spouses_write_mods ON public.external_spouses
  USING      (EXISTS (SELECT 1 FROM public.profiles p WHERE (p.id = auth.uid() OR p.id = NULLIF(auth.jwt()->'app_metadata'->>'profile_id','')::uuid) AND p.role = ANY (ARRAY['owner','admin','monitor','supervisor'])))
  WITH CHECK (EXISTS (SELECT 1 FROM public.profiles p WHERE (p.id = auth.uid() OR p.id = NULLIF(auth.jwt()->'app_metadata'->>'profile_id','')::uuid) AND p.role = ANY (ARRAY['owner','admin','monitor','supervisor'])));

ALTER POLICY web_relatives_select ON public.web_relatives
  USING      (EXISTS (SELECT 1 FROM public.profiles p WHERE (p.id = auth.uid() OR p.id = NULLIF(auth.jwt()->'app_metadata'->>'profile_id','')::uuid) AND p.role = ANY (ARRAY['owner','admin','monitor','supervisor'])));

ALTER POLICY web_relatives_write ON public.web_relatives
  USING      (EXISTS (SELECT 1 FROM public.profiles p WHERE (p.id = auth.uid() OR p.id = NULLIF(auth.jwt()->'app_metadata'->>'profile_id','')::uuid) AND p.role = ANY (ARRAY['owner','admin','monitor'])))
  WITH CHECK (EXISTS (SELECT 1 FROM public.profiles p WHERE (p.id = auth.uid() OR p.id = NULLIF(auth.jwt()->'app_metadata'->>'profile_id','')::uuid) AND p.role = ANY (ARRAY['owner','admin','monitor'])));;
