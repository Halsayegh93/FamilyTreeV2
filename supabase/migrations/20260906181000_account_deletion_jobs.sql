begin;
-- Durable, server-only cleanup manifest. Retrying a partial deletion is safe.
create table if not exists public.account_deletion_jobs (
  auth_user_id uuid primary key,
  profile_id uuid not null,
  storage_files jsonb not null default '[]',
  phase text not null default 'prepared',
  created_at timestamptz not null default now()
);
alter table public.account_deletion_jobs enable row level security;
revoke all on public.account_deletion_jobs from public, anon, authenticated;
grant all on public.account_deletion_jobs to service_role;

create or replace function public.prepare_account_deletion(p_auth_id uuid, p_profile_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare job public.account_deletion_jobs; target_role text; files jsonb;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'service_only' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_auth_id::text,0));
  select * into job from public.account_deletion_jobs where auth_user_id=p_auth_id;
  if found then
    if job.profile_id <> p_profile_id then raise exception 'profile_binding_changed'; end if;
    return to_jsonb(job);
  end if;
  select role into target_role from public.profiles where id=p_profile_id for update;
  if target_role = 'owner' then raise exception 'owner_account_protected' using errcode='42501'; end if;
  -- Never trust arbitrary URLs supplied in a profile to delete service-owned files.
  select coalesce(jsonb_agg(jsonb_build_object('bucket',o.bucket_id,'path',o.name)), '[]'::jsonb)
  into files from storage.objects o
  where (coalesce(to_jsonb(o)->>'owner_id',to_jsonb(o)->>'owner') in (p_auth_id::text,p_profile_id::text)
          and o.bucket_id in ('news','stories','family-gallery','family-archive'))
     or (o.bucket_id='avatars' and lower(o.name) in (p_profile_id::text||'.jpg','cover_'||p_profile_id::text||'.jpg'))
     or (o.bucket_id='news' and lower(o.name) like 'news/'||p_profile_id::text||'/%')
     or (o.bucket_id='member-gallery' and lower(o.name) like p_profile_id::text||'/%')
     or (o.bucket_id='avatars' and lower(o.name) in (
       select 'project-logos/'||id::text||'.jpg' from public.projects where owner_id=p_profile_id));
  insert into public.account_deletion_jobs(auth_user_id,profile_id,storage_files)
  values(p_auth_id,p_profile_id,files) returning * into job;
  -- Immediately revoke active access while retaining auth for retrying cleanup.
  update public.profiles set status='frozen' where id=p_profile_id;
  return to_jsonb(job);
end;
$$;

create or replace function public.finalize_account_deletion(p_auth_id uuid)
returns void language plpgsql security definer set search_path = public as $$
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
  -- Keep genealogy links and the stable node id, remove personal profile fields.
  patch := jsonb_build_object('first_name','عضو محذوف','full_name','عضو محذوف',
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
    update public.women_members set first_name='عضو محذوف',full_name='عضو محذوف',
      birth_date=null,death_date=null,photo_url=null,avatar_url=null,linked_user_id=null
    where id=job.profile_id or linked_user_id in (job.profile_id,p_auth_id);
  end if;
  update public.account_deletion_jobs set phase='data_deleted'  where auth_user_id=p_auth_id;
end;
$$;
revoke all on function public.prepare_account_deletion(uuid,uuid) from public,anon,authenticated;
revoke all on function public.finalize_account_deletion(uuid) from public,anon,authenticated;
grant execute on function public.prepare_account_deletion(uuid,uuid) to service_role;
grant execute on function public.finalize_account_deletion(uuid) to service_role;
create or replace function public.prepare_phone_unlink(p_profile_id uuid)
returns uuid[] language plpgsql security definer set search_path = public as $$
declare ids uuid[]; target_role text;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'service_only' using errcode='42501'; end if;
  select role into target_role from public.profiles where id=p_profile_id for update;
  if not found then raise exception 'profile_not_found'; end if;
  if target_role='owner' then raise exception 'owner_account_protected' using errcode='42501'; end if;
  select coalesce(array_agg(id),'{}'::uuid[]) into ids from auth.users
    where id=p_profile_id or raw_app_meta_data->>'profile_id'=p_profile_id::text;
  update public.profiles set phone_number=null,status='pending' where id=p_profile_id;
  delete from public.device_tokens where member_id=p_profile_id or member_id=any(ids);
  return ids;
end;
$$;
revoke all on function public.prepare_phone_unlink(uuid) from public,anon,authenticated;
grant execute on function public.prepare_phone_unlink(uuid) to service_role;
commit;
