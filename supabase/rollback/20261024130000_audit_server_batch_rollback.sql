-- تراجع 20261024130000_audit_server_batch — يعيد الحي كما كان يوم ٢٠٢٦-١٠-٢٤ حرفياً
-- (الدوال المعدّلة بالاستبدال تُعاد بالاستبدال العكسي؛ المكتوبة كاملة تُعاد بنصّها الحي)

-- ١) شجرة النساء
do $$
declare
  f regprocedure;
  def text;
begin
  for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public'
              and p.proname in ('add_self_mother', 'set_self_mother', 'set_self_wife', 'remove_self_wife',
                                'reorder_self_women_children', 'add_self_wife', 'set_self_wife_hidden')
  loop
    def := pg_get_functiondef(f);
    if position('public.my_active_women_node()' in def) > 0 then
      execute replace(def, 'public.my_active_women_node()', 'public.my_women_node()');
    end if;
  end loop;
end $$;

CREATE OR REPLACE FUNCTION public.remove_self_woman_child(p_child_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := public.my_women_node();
begin
  if me is null then raise exception 'no_node'; end if;
  if not exists (select 1 from public.women_members where id = p_child_id and parent_id = me) then
    raise exception 'not_your_child';
  end if;
  delete from public.women_members where id = p_child_id;
end; $function$
;

CREATE OR REPLACE FUNCTION public.update_self_woman_child(p_child_id uuid, p_first_name text, p_full_name text, p_birth date, p_deceased boolean, p_death date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := public.my_women_node();
begin
  if me is null then raise exception 'no_node'; end if;
  if not exists (select 1 from public.women_members where id = p_child_id and parent_id = me) then
    raise exception 'not_your_child';
  end if;
  update public.women_members
     set first_name  = coalesce(nullif(trim(p_first_name), ''), first_name),
         full_name   = coalesce(nullif(trim(p_full_name), ''), full_name),
         birth_date  = p_birth,
         is_deceased = coalesce(p_deceased, false),
         death_date  = case when p_deceased then p_death else null end
   where id = p_child_id;
end; $function$
;

drop function if exists public.my_active_women_node();

-- ٢) الشجرة
do $$
declare
  def text;
begin
  def := pg_get_functiondef('public.add_family_child(uuid,text,text,date,boolean,date,integer,text)'::regprocedure);
  def := replace(def,
    'if not (coalesce(public.current_user_role(), '''') in (''owner'', ''admin'', ''monitor'')'
    || ' or (p_parent_id = any (array[auth.uid(), public.current_profile_id()])'
    || ' and coalesce(public.current_user_role(), '''') in (''member'', ''supervisor''))) then',
    'if not (public.is_moderator() or p_parent_id = auth.uid()) then');
  execute def;

  def := pg_get_functiondef('public.move_child_gender(uuid,text)'::regprocedure);
  def := replace(def,
    'if coalesce(public.current_user_role(), '''') not in (''owner'', ''admin'', ''monitor'') then',
    'if not public.is_moderator() then');
  execute def;

  -- ٣) آخر دخول
  def := pg_get_functiondef('public.get_members_last_signin()'::regprocedure);
  def := replace(def,
    E'  caller_role := public.current_user_role();\n  if caller_role is null or caller_role not in (''owner'', ''admin'', ''monitor'') then',
    E'  select role into caller_role from public.profiles where id = public.current_profile_id();\n  if caller_role is null or caller_role not in (''owner'', ''admin'', ''monitor'', ''supervisor'') then');
  execute def;
end $$;

-- ٤) الأخبار
drop policy if exists news_update_moderator on public.news;
create policy news_update_moderator on public.news for update
  using (current_user_role() = any (array['supervisor', 'monitor', 'admin', 'owner']))
  with check (current_user_role() = any (array['supervisor', 'monitor', 'admin', 'owner']));
drop policy if exists news_insert_member_own on storage.objects;
drop policy if exists news_update_admin on storage.objects;
create policy news_update_admin on storage.objects for update to authenticated
  using (bucket_id = 'news' and current_user_role() = any (array['owner', 'admin', 'monitor', 'supervisor']));
drop policy if exists news_delete_admin on storage.objects;
create policy news_delete_admin on storage.objects for delete to authenticated
  using (bucket_id = 'news' and current_user_role() = any (array['owner', 'admin', 'monitor', 'supervisor']));

-- ٥) حذف طلبات المراجعة
drop policy if exists admin_requests_delete_own_pending on public.admin_requests;
drop policy if exists admin_requests_delete_by_scope on public.admin_requests;
create policy admin_requests_delete_by_scope on public.admin_requests for delete to authenticated
  using (can_handle_admin_request(request_type));

-- ٦) قفل محتوى الطلب
drop trigger if exists trg_admin_request_payload_lock on public.admin_requests;
drop function if exists public.trg_admin_request_payload_lock();

-- ٧) ملفات المكتبة
drop policy if exists family_archive_storage_read on storage.objects;
create policy family_archive_storage_read on storage.objects for select to authenticated
  using (bucket_id = 'family-archive' and auth.uid() is not null);

-- ٨) سرد المستودعات العامة
drop policy if exists "Public Access to gallery" on storage.objects;
create policy "Public Access to gallery" on storage.objects for select using (bucket_id = 'gallery');
drop policy if exists "Public Access to news" on storage.objects;
create policy "Public Access to news" on storage.objects for select using (bucket_id = 'news');
drop policy if exists family_gallery_storage_read on storage.objects;
create policy family_gallery_storage_read on storage.objects for select using (bucket_id = 'family-gallery');
create policy stories_public_read on storage.objects for select using (bucket_id = 'stories');
