-- حذف الحساب يُبقي اسم العضو في الشجرة (طلب المالك ٢٠٢٦-١٠-٠٥: «تبي اسمه بدون عضو محذوف»).
-- قبل: finalize_account_deletion يكتب «عضو محذوف» مكان الاسم في profiles وwomen_members.
-- بعد: الاسم (first_name/full_name) يبقى كسجلّ نسب للعائلة؛ يبقى حذف الحساب وكل البيانات الشخصية الأخرى كما هو
-- (الرقم، البريد، المعرّف، تاريخا الميلاد والوفاة، الصور، النبذة، الأدوار، الأجهزة، المحتوى، حساب الدخول).
-- التراجع: supabase/rollback/20261005190000_keep_name_on_account_deletion_rollback.sql
-- التجربة: cd supabase/tests/family_links && node keep_name_on_deletion.test.mjs
CREATE OR REPLACE FUNCTION public.finalize_account_deletion(p_auth_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare job public.account_deletion_jobs; spec record; patch jsonb; assignments text;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'service_only' using errcode='42501'; end if;
  select * into job from public.account_deletion_jobs where auth_user_id=p_auth_id for update;
  if not found then raise exception 'deletion_not_prepared'; end if;
  if job.phase='data_deleted' then return; end if;
  -- One database transaction: an error rolls back all row cleanup.
  delete from public.news where author_id=job.profile_id;
  delete from public.news_comments where author_id in (job.profile_id,p_auth_id);
  delete from public.news_likes where member_id in (job.profile_id,p_auth_id);
  delete from public.news_poll_votes where member_id in (job.profile_id,p_auth_id);
  delete from public.notifications where target_member_id=job.profile_id or created_by=job.profile_id;
  delete from public.device_tokens where member_id in (job.profile_id,p_auth_id);
  delete from public.admin_requests where member_id=job.profile_id or requester_id=job.profile_id;
  delete from public.diwaniyas where owner_id=job.profile_id;
  delete from public.projects where owner_id=job.profile_id;
  delete from public.member_gallery_photos where member_id=job.profile_id;
  -- Optional features vary between installations. Skip absent tables/columns only,
  -- never swallow execution errors in a table that is present.
  for spec in select * from (values
    ('news','posted_by'), ('family_stories','member_id'), ('family_stories','created_by'),
    ('family_story_views','viewer_id'), ('gallery_photos','uploaded_by'),
    ('family_archive','uploaded_by'), ('web_push_subscriptions','member_id'),
    ('blocked_users','blocker_id'), ('blocked_users','blocked_id')
  ) as t(tbl,col) loop
    if exists(select 1 from information_schema.columns where table_schema='public' and table_name=spec.tbl and column_name=spec.col) then
      execute format('delete from public.%I where %I = any($1)',spec.tbl,spec.col)
      using array[job.profile_id,p_auth_id];
    end if;
  end loop;
  -- Keep genealogy links, the stable node id AND the member's name (طلب المالك ٢٠٢٦-١٠-٠٥ «اسمه بدون عضو محذوف»):
  -- the tree keeps «فلان بن فلان» as a family record; personal profile fields and the account are removed.
  patch := jsonb_build_object(
    'phone_number',null,'email',null,'username',null,'birth_date',null,'death_date',null,
    'photo_url',null,'avatar_url',null,'cover_url',null,'bio',null,'bio_json','[]'::jsonb,
    'role','member','status','deleted','is_phone_hidden',true,'is_birth_date_hidden',true,
    'is_phone_verified',false,'is_admin',false,'is_approved',false,'is_deceased',false,
    'terms_accepted_at',null,'last_seen_at',null,'last_active_at',null,'current_screen',null,
    'current_screen_source',null,'family_name',null,'is_married',false);
  select string_agg(format('%I = r.%I',a.attname,a.attname),', ') into assignments
  from pg_attribute a where a.attrelid='public.profiles'::regclass and a.attnum>0 and not a.attisdropped and patch ? a.attname;
  execute 'update public.profiles p set '||assignments||
    ' from jsonb_populate_record(null::public.profiles,$1) r where p.id=$2'
    using patch,job.profile_id;
  if to_regclass('public.women_members') is not null then
    update public.women_members set
      birth_date=null,death_date=null,photo_url=null,avatar_url=null,linked_user_id=null
    where id=job.profile_id or linked_user_id in (job.profile_id,p_auth_id);
  end if;
  update public.account_deletion_jobs set phase='data_deleted'  where auth_user_id=p_auth_id;
end;
$function$;
