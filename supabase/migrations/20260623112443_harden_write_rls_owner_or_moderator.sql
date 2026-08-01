-- مساعد: هل المستخدم الحالي من الإدارة؟ (SECURITY DEFINER يتجاوز RLS بأمان)
create or replace function public.is_moderator()
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('owner','admin','monitor','supervisor')
  );
$$;
grant execute on function public.is_moderator() to authenticated;

-- diwaniyas (owner_id): التعديل/الحذف للمالك أو الإدارة فقط
drop policy if exists diwaniyas_update on public.diwaniyas;
create policy diwaniyas_update on public.diwaniyas for update to authenticated
  using (owner_id = auth.uid() or public.is_moderator())
  with check (owner_id = auth.uid() or public.is_moderator());
drop policy if exists diwaniyas_delete on public.diwaniyas;
create policy diwaniyas_delete on public.diwaniyas for delete to authenticated
  using (owner_id = auth.uid() or public.is_moderator());

-- projects (owner_id)
drop policy if exists projects_update on public.projects;
create policy projects_update on public.projects for update to authenticated
  using (owner_id = auth.uid() or public.is_moderator())
  with check (owner_id = auth.uid() or public.is_moderator());
drop policy if exists projects_delete on public.projects;
create policy projects_delete on public.projects for delete to authenticated
  using (owner_id = auth.uid() or public.is_moderator());

-- family_stories (created_by)
drop policy if exists family_stories_update on public.family_stories;
create policy family_stories_update on public.family_stories for update to authenticated
  using (created_by = auth.uid() or public.is_moderator())
  with check (created_by = auth.uid() or public.is_moderator());
drop policy if exists family_stories_delete on public.family_stories;
create policy family_stories_delete on public.family_stories for delete to authenticated
  using (created_by = auth.uid() or public.is_moderator());

-- member_gallery_photos (created_by)
drop policy if exists member_gallery_photos_update on public.member_gallery_photos;
create policy member_gallery_photos_update on public.member_gallery_photos for update to authenticated
  using (created_by = auth.uid() or public.is_moderator())
  with check (created_by = auth.uid() or public.is_moderator());
drop policy if exists member_gallery_photos_delete on public.member_gallery_photos;
create policy member_gallery_photos_delete on public.member_gallery_photos for delete to authenticated
  using (created_by = auth.uid() or public.is_moderator());

-- device_tokens (member_id): كل مستخدم يدير أجهزته فقط
drop policy if exists device_tokens_update_self on public.device_tokens;
create policy device_tokens_update_self on public.device_tokens for update to authenticated
  using (member_id = auth.uid()) with check (member_id = auth.uid());
drop policy if exists device_tokens_insert_self on public.device_tokens;
create policy device_tokens_insert_self on public.device_tokens for insert to authenticated
  with check (member_id = auth.uid());;
