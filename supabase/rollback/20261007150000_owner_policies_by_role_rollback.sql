-- تراجع 20261007150000: سياسات app_settings والمشاريع كما كانت على السيرفر الحي قبل ٢٠٢٦-١٠-٠٧

drop policy if exists "Owner can update app_settings" on public.app_settings;
create policy "Owner can update app_settings" on public.app_settings
  for update to authenticated
  using ((EXISTS ( SELECT 1
     FROM public.profiles
    WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'owner'::text)))));

drop policy if exists projects_update on public.projects;
create policy projects_update on public.projects
  for update to authenticated
  using (((owner_id = auth.uid()) OR (public.current_user_role() = ANY (ARRAY['owner'::text, 'admin'::text]))))
  with check (((owner_id = auth.uid()) OR (public.current_user_role() = ANY (ARRAY['owner'::text, 'admin'::text]))));

drop policy if exists projects_delete on public.projects;
create policy projects_delete on public.projects
  for delete to authenticated
  using (((owner_id = auth.uid()) OR (public.current_user_role() = ANY (ARRAY['owner'::text, 'admin'::text]))));
