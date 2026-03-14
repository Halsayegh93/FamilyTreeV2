create extension if not exists "hypopg" with schema "extensions";

create extension if not exists "index_advisor" with schema "extensions";

drop extension if exists "pg_net";

drop policy "member_gallery_update_self" on "public"."member_gallery_photos";

alter table "public"."admin_requests" drop constraint "admin_requests_status_check";

alter table "public"."diwaniyas" drop constraint "diwaniyas_owner_id_fkey";

alter table "public"."profiles" drop constraint "profiles_role_check";

alter table "public"."profiles" drop constraint "profiles_status_check";

drop index if exists "public"."idx_gallery_photos_created_at";

drop index if exists "public"."idx_news_author_id";

drop index if exists "public"."idx_news_comments_created_at";

drop index if exists "public"."idx_notifications_created_at";

drop index if exists "public"."idx_notifications_target";

drop index if exists "public"."idx_profiles_created_at";

drop index if exists "public"."idx_profiles_full_name";

drop index if exists "public"."idx_profiles_sort_order";

drop index if exists "public"."idx_profiles_status";

drop index if exists "public"."idx_profiles_status_role";


  create table "public"."join_requests" (
    "id" uuid not null default gen_random_uuid(),
    "full_name" text,
    "phone_number" text,
    "birth_date" date,
    "suggested_father_id" uuid,
    "status" text default 'pending'::text
      );



  create table "public"."user_timeline" (
    "id" uuid not null default gen_random_uuid(),
    "user_id" uuid,
    "year" text,
    "title" text not null,
    "details" text,
    "created_at" timestamp with time zone default now()
      );


alter table "public"."admin_requests" alter column "created_at" set default now();

alter table "public"."admin_requests" alter column "created_at" drop not null;

alter table "public"."admin_requests" alter column "id" set default extensions.uuid_generate_v4();

alter table "public"."admin_requests" alter column "member_id" drop not null;

alter table "public"."admin_requests" alter column "request_type" set default 'deceased_report'::text;

alter table "public"."admin_requests" alter column "request_type" drop not null;

alter table "public"."admin_requests" alter column "status" drop not null;

alter table "public"."diwaniyas" add column "location_url" text;

alter table "public"."diwaniyas" add column "name" text;

alter table "public"."diwaniyas" add column "status" text default 'pending'::text;

alter table "public"."diwaniyas" add column "timing" text;

alter table "public"."diwaniyas" alter column "approval_status" drop not null;

alter table "public"."diwaniyas" alter column "created_at" drop not null;

alter table "public"."diwaniyas" alter column "owner_id" drop not null;

alter table "public"."diwaniyas" alter column "owner_name" drop not null;

alter table "public"."diwaniyas" alter column "title" drop not null;

alter table "public"."news" alter column "approval_status" drop not null;

alter table "public"."news" alter column "author_id" drop not null;

alter table "public"."news" alter column "created_at" drop not null;

alter table "public"."news" alter column "poll_options" drop default;

alter table "public"."news" alter column "poll_options" drop not null;

alter table "public"."profiles" add column "bio" jsonb default '[]'::jsonb;

alter table "public"."profiles" add column "is_admin" boolean default false;

alter table "public"."profiles" add column "is_approved" boolean default false;

alter table "public"."profiles" add column "is_phone_verified" boolean not null default false;

alter table "public"."profiles" add column "photo_url" text;

alter table "public"."profiles" add column "sons_ids" uuid[] default '{}'::uuid[];

alter table "public"."profiles" alter column "bio_json" drop not null;

alter table "public"."profiles" alter column "created_at" set default now();

alter table "public"."profiles" alter column "created_at" drop not null;

alter table "public"."profiles" alter column "first_name" set default 'Nullable'::text;

alter table "public"."profiles" alter column "first_name" drop not null;

alter table "public"."profiles" alter column "full_name" drop not null;

alter table "public"."profiles" alter column "is_deceased" drop not null;

alter table "public"."profiles" alter column "is_hidden_from_tree" drop not null;

alter table "public"."profiles" alter column "is_married" drop not null;

alter table "public"."profiles" alter column "is_phone_hidden" drop not null;

alter table "public"."profiles" alter column "role" set default 'user'::text;

alter table "public"."profiles" alter column "role" drop not null;

alter table "public"."profiles" alter column "sort_order" drop not null;

alter table "public"."profiles" alter column "status" drop not null;

CREATE UNIQUE INDEX join_requests_pkey ON public.join_requests USING btree (id);

CREATE UNIQUE INDEX user_timeline_pkey ON public.user_timeline USING btree (id);

alter table "public"."join_requests" add constraint "join_requests_pkey" PRIMARY KEY using index "join_requests_pkey";

alter table "public"."user_timeline" add constraint "user_timeline_pkey" PRIMARY KEY using index "user_timeline_pkey";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.handle_new_user_by_phone()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  -- 1. البحث عن سجل في profiles يطابق رقم هاتف المستخدم الجديد
  -- نستخدم new.phone وهو الرقم الذي سجل به المستخدم في Auth
  if exists (select 1 from public.profiles where phone_number = new.phone) then
    
    -- 2. إذا وجدنا السجل، نقوم بتحديث الـ id ليطابق معرف الـ Auth الجديد
    -- ملاحظة: قد تحتاج لتحديث سجلات الأبناء أيضاً إذا كان المعرف القديم مستخدماً كـ father_id
    update public.profiles
    set id = new.id
    where phone_number = new.phone;
    
  else
    -- 3. إذا لم يوجد سجل سابق، ننشئ واحداً جديداً
    insert into public.profiles (id, phone_number, full_name, role)
    values (
      new.id, 
      new.phone, 
      new.raw_user_meta_data->>'full_name', 
      'member'
    );
  end if;
  
  return new;
end;
$function$
;

grant delete on table "public"."join_requests" to "anon";

grant insert on table "public"."join_requests" to "anon";

grant references on table "public"."join_requests" to "anon";

grant select on table "public"."join_requests" to "anon";

grant trigger on table "public"."join_requests" to "anon";

grant truncate on table "public"."join_requests" to "anon";

grant update on table "public"."join_requests" to "anon";

grant delete on table "public"."join_requests" to "authenticated";

grant insert on table "public"."join_requests" to "authenticated";

grant references on table "public"."join_requests" to "authenticated";

grant select on table "public"."join_requests" to "authenticated";

grant trigger on table "public"."join_requests" to "authenticated";

grant truncate on table "public"."join_requests" to "authenticated";

grant update on table "public"."join_requests" to "authenticated";

grant delete on table "public"."join_requests" to "service_role";

grant insert on table "public"."join_requests" to "service_role";

grant references on table "public"."join_requests" to "service_role";

grant select on table "public"."join_requests" to "service_role";

grant trigger on table "public"."join_requests" to "service_role";

grant truncate on table "public"."join_requests" to "service_role";

grant update on table "public"."join_requests" to "service_role";

grant delete on table "public"."user_timeline" to "anon";

grant insert on table "public"."user_timeline" to "anon";

grant references on table "public"."user_timeline" to "anon";

grant select on table "public"."user_timeline" to "anon";

grant trigger on table "public"."user_timeline" to "anon";

grant truncate on table "public"."user_timeline" to "anon";

grant update on table "public"."user_timeline" to "anon";

grant delete on table "public"."user_timeline" to "authenticated";

grant insert on table "public"."user_timeline" to "authenticated";

grant references on table "public"."user_timeline" to "authenticated";

grant select on table "public"."user_timeline" to "authenticated";

grant trigger on table "public"."user_timeline" to "authenticated";

grant truncate on table "public"."user_timeline" to "authenticated";

grant update on table "public"."user_timeline" to "authenticated";

grant delete on table "public"."user_timeline" to "service_role";

grant insert on table "public"."user_timeline" to "service_role";

grant references on table "public"."user_timeline" to "service_role";

grant select on table "public"."user_timeline" to "service_role";

grant trigger on table "public"."user_timeline" to "service_role";

grant truncate on table "public"."user_timeline" to "service_role";

grant update on table "public"."user_timeline" to "service_role";


  create policy "الجميع يشاهد الأخبار"
  on "public"."news"
  as permissive
  for select
  to public
using (true);



  create policy "المدراء فقط يضيفون أخبار"
  on "public"."news"
  as permissive
  for insert
  to public
with check (true);



  create policy "Admins and Supervisors can update any profile"
  on "public"."profiles"
  as permissive
  for update
  to public
using ((EXISTS ( SELECT 1
   FROM public.profiles profiles_1
  WHERE ((profiles_1.id = auth.uid()) AND ((profiles_1.role = 'admin'::text) OR (profiles_1.role = 'supervisor'::text))))));



  create policy "Admins can delete any profile"
  on "public"."profiles"
  as permissive
  for delete
  to authenticated
using ((( SELECT profiles_1.role
   FROM public.profiles profiles_1
  WHERE (profiles_1.id = auth.uid())) = 'admin'::text));



  create policy "Allow authenticated users to insert profiles"
  on "public"."profiles"
  as permissive
  for insert
  to authenticated
with check ((auth.role() = 'authenticated'::text));



  create policy "Allow system to link profiles"
  on "public"."profiles"
  as permissive
  for update
  to public
using (true)
with check (true);



  create policy "Allow users to update profiles"
  on "public"."profiles"
  as permissive
  for update
  to authenticated
using ((auth.role() = 'authenticated'::text));



  create policy "Authenticated users can view all profiles"
  on "public"."profiles"
  as permissive
  for select
  to authenticated
using (true);



  create policy "Users can update their own profiles"
  on "public"."profiles"
  as permissive
  for update
  to public
using ((auth.uid() = id))
with check ((auth.uid() = id));



  create policy "الكل يشاهد البيانات"
  on "public"."profiles"
  as permissive
  for select
  to public
using (true);



  create policy "المستخدم يضيف بياناته"
  on "public"."profiles"
  as permissive
  for insert
  to public
with check ((auth.uid() = id));



  create policy "المستخدم يعدل بياناته فقط"
  on "public"."profiles"
  as permissive
  for update
  to public
using ((auth.uid() = id));


CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_by_phone();


  create policy "Auth Delete to gallery"
  on "storage"."objects"
  as permissive
  for delete
  to authenticated
using ((bucket_id = 'gallery'::text));



  create policy "Auth Delete to news"
  on "storage"."objects"
  as permissive
  for delete
  to authenticated
using ((bucket_id = 'news'::text));



  create policy "Auth Insert to gallery"
  on "storage"."objects"
  as permissive
  for insert
  to authenticated
with check ((bucket_id = 'gallery'::text));



  create policy "Auth Insert to news"
  on "storage"."objects"
  as permissive
  for insert
  to authenticated
with check ((bucket_id = 'news'::text));



  create policy "Auth Update to gallery"
  on "storage"."objects"
  as permissive
  for update
  to authenticated
using ((bucket_id = 'gallery'::text));



  create policy "Auth Update to news"
  on "storage"."objects"
  as permissive
  for update
  to authenticated
using ((bucket_id = 'news'::text));



  create policy "Give users authenticated access to folder 1oj01fe_0"
  on "storage"."objects"
  as permissive
  for insert
  to authenticated
with check (true);



  create policy "Give users authenticated access to folder 1oj01fe_1"
  on "storage"."objects"
  as permissive
  for select
  to authenticated
using (true);



  create policy "Give users authenticated access to folder 1oj01fe_2"
  on "storage"."objects"
  as permissive
  for update
  to authenticated
using (true);



  create policy "Give users authenticated access to folder 1oj01fe_3"
  on "storage"."objects"
  as permissive
  for delete
  to authenticated
using (true);



  create policy "Public Access to gallery"
  on "storage"."objects"
  as permissive
  for select
  to public
using ((bucket_id = 'gallery'::text));



  create policy "Public Access to news"
  on "storage"."objects"
  as permissive
  for select
  to public
using ((bucket_id = 'news'::text));



