-- تراجع: سياسات شجرة النساء والأزواج كما كانت (profiles.role وحده، والمشرف يكتب)، وإزالة حارس المرسل
alter policy women_members_write on public.women_members
  using (exists (select 1 from public.profiles p
                 where (p.id = auth.uid() or p.id = (nullif((auth.jwt() -> 'app_metadata') ->> 'profile_id', ''))::uuid)
                   and p.role = any (array['owner','admin','monitor'])))
  with check (exists (select 1 from public.profiles p
                      where (p.id = auth.uid() or p.id = (nullif((auth.jwt() -> 'app_metadata') ->> 'profile_id', ''))::uuid)
                        and p.role = any (array['owner','admin','monitor'])));

alter policy external_spouses_select_mods on public.external_spouses
  using (exists (select 1 from public.profiles p
                 where (p.id = auth.uid() or p.id = (nullif((auth.jwt() -> 'app_metadata') ->> 'profile_id', ''))::uuid)
                   and p.role = any (array['owner','admin','monitor','supervisor'])));

alter policy external_spouses_write_mods on public.external_spouses
  using (exists (select 1 from public.profiles p
                 where (p.id = auth.uid() or p.id = (nullif((auth.jwt() -> 'app_metadata') ->> 'profile_id', ''))::uuid)
                   and p.role = any (array['owner','admin','monitor','supervisor'])))
  with check (exists (select 1 from public.profiles p
                      where (p.id = auth.uid() or p.id = (nullif((auth.jwt() -> 'app_metadata') ->> 'profile_id', ''))::uuid)
                        and p.role = any (array['owner','admin','monitor','supervisor'])));

drop trigger if exists trg_a_guard_notification_sender on public.notifications;
drop function if exists public.guard_notification_sender();
