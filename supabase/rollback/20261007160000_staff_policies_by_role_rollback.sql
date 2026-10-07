-- تراجع 20261007160000: سياسات الإدارة الخمس كما كانت على السيرفر الحي قبل ٢٠٢٦-١٠-٠٧ (من pg_policies حرفياً)

drop policy if exists home_sections_write on public.home_sections;
create policy home_sections_write on public.home_sections
  for all to authenticated
  using ((EXISTS ( SELECT 1
     FROM public.profiles p
    WHERE ((p.id = auth.uid()) AND (p.role = ANY (ARRAY['owner'::text, 'admin'::text, 'monitor'::text]))))))
  with check ((EXISTS ( SELECT 1
     FROM public.profiles p
    WHERE ((p.id = auth.uid()) AND (p.role = ANY (ARRAY['owner'::text, 'admin'::text, 'monitor'::text]))))));

drop policy if exists web_sessions_admin_select on public.web_sessions;
create policy web_sessions_admin_select on public.web_sessions
  for select to public
  using ((EXISTS ( SELECT 1
     FROM public.profiles p
    WHERE ((p.id = auth.uid()) AND (p.role = ANY (ARRAY['owner'::text, 'admin'::text, 'monitor'::text, 'supervisor'::text]))))));

drop policy if exists web_push_subs_admin_select on public.web_push_subscriptions;
create policy web_push_subs_admin_select on public.web_push_subscriptions
  for select to public
  using ((EXISTS ( SELECT 1
     FROM public.profiles p
    WHERE ((p.id = auth.uid()) AND (p.role = ANY (ARRAY['owner'::text, 'admin'::text, 'monitor'::text, 'supervisor'::text]))))));

drop policy if exists web_relatives_select on public.web_relatives;
create policy web_relatives_select on public.web_relatives
  for select to authenticated
  using ((EXISTS ( SELECT 1
     FROM public.profiles p
    WHERE (((p.id = auth.uid()) OR (p.id = (NULLIF(((auth.jwt() -> 'app_metadata'::text) ->> 'profile_id'::text), ''::text))::uuid)) AND (p.role = ANY (ARRAY['owner'::text, 'admin'::text, 'monitor'::text, 'supervisor'::text]))))));

drop policy if exists web_relatives_write on public.web_relatives;
create policy web_relatives_write on public.web_relatives
  for all to authenticated
  using ((EXISTS ( SELECT 1
     FROM public.profiles p
    WHERE (((p.id = auth.uid()) OR (p.id = (NULLIF(((auth.jwt() -> 'app_metadata'::text) ->> 'profile_id'::text), ''::text))::uuid)) AND (p.role = ANY (ARRAY['owner'::text, 'admin'::text, 'monitor'::text]))))))
  with check ((EXISTS ( SELECT 1
     FROM public.profiles p
    WHERE (((p.id = auth.uid()) OR (p.id = (NULLIF(((auth.jwt() -> 'app_metadata'::text) ->> 'profile_id'::text), ''::text))::uuid)) AND (p.role = ANY (ARRAY['owner'::text, 'admin'::text, 'monitor'::text]))))));
