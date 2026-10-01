-- نسخة مصغّرة من السيرفر الحي (٢٠٢٦-١٠-٠١) لتجربة حماية الروابط محلياً فقط.
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role; end if;
end $$;

create schema if not exists auth;
create table auth.users (id uuid primary key, phone text, raw_app_meta_data jsonb default '{}'::jsonb);
create or replace function auth.uid() returns uuid language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
                  nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')::uuid $$;
create or replace function auth.jwt() returns jsonb language sql stable as $$
  select nullif(current_setting('request.jwt.claims', true), '')::jsonb $$;
create or replace function auth.role() returns text language sql stable as $$
  select nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role' $$;

create table public.profiles (
  id uuid primary key default gen_random_uuid(), first_name text, full_name text, phone_number text,
  birth_date date, death_date date, is_deceased boolean default false, role text default 'user',
  father_id uuid, photo_url text, is_phone_hidden boolean default false, is_hidden_from_tree boolean default false,
  sort_order integer default 0, bio_json jsonb default '[]'::jsonb, sons_ids uuid[] default '{}'::uuid[],
  status text default 'pending', created_at timestamptz default now(), is_married boolean default false,
  avatar_url text, bio jsonb default '[]'::jsonb, is_approved boolean default false, is_admin boolean default false,
  is_phone_verified boolean default false, is_birth_date_hidden boolean default false, cover_url text,
  badge_enabled boolean default true, gender text, updated_by uuid, updated_at timestamptz default now(),
  is_hr_member boolean default false, hr_status text, last_seen_at timestamptz, registration_platform text default 'ios',
  username text, last_active_at timestamptz, current_screen text, current_screen_source text, email text,
  mother_id uuid, husband_id uuid, terms_accepted_at timestamptz, family_name text,
  death_date_unknown boolean default false, avatar_unavailable boolean default false, notification_prefs jsonb default '{}'::jsonb
);
alter table public.profiles
  add constraint profiles_father_id_fkey  foreign key (father_id)  references public.profiles(id) on delete set null,
  add constraint profiles_mother_id_fkey  foreign key (mother_id)  references public.profiles(id) on delete set null,
  add constraint profiles_husband_id_fkey foreign key (husband_id) references public.profiles(id) on delete set null,
  add constraint profiles_updated_by_fkey foreign key (updated_by) references public.profiles(id) on delete set null;

create table public.women_members (
  id uuid primary key default gen_random_uuid(), first_name text default '', full_name text default '', parent_id uuid,
  sort_order integer default 0, gender text default 'female', is_deceased boolean default false, birth_date date,
  death_date date, is_hidden_from_tree boolean default false, created_at timestamptz default now(), mother_id uuid,
  husband_id uuid, photo_url text, avatar_url text, linked_user_id uuid, is_married boolean, mother_name text,
  is_web_only boolean default false
);
alter table public.women_members
  add constraint women_members_parent_id_fkey  foreign key (parent_id)  references public.women_members(id) on delete set null,
  add constraint women_members_mother_id_fkey  foreign key (mother_id)  references public.women_members(id) on delete set null,
  add constraint women_members_husband_id_fkey foreign key (husband_id) references public.women_members(id) on delete set null,
  add constraint women_members_linked_user_id_fkey foreign key (linked_user_id) references public.profiles(id) on delete set null;

create table public.notifications (id uuid primary key default gen_random_uuid(),
  target_member_id uuid references public.profiles(id) on delete cascade,
  created_by uuid references public.profiles(id) on delete set null,
  title text, body text, kind text, is_read boolean default false, created_at timestamptz default now());
create table public.device_tokens (id uuid primary key default gen_random_uuid(),
  member_id uuid references public.profiles(id) on delete cascade, token text);
create table public.member_gallery_photos (id uuid primary key default gen_random_uuid(),
  member_id uuid references public.profiles(id) on delete cascade);
create table public.admin_requests (id uuid primary key default gen_random_uuid(),
  member_id uuid references public.profiles(id) on delete cascade,
  requester_id uuid references public.profiles(id) on delete set null,
  request_type text, status text);
create table public.external_spouses (id uuid primary key default gen_random_uuid(),
  woman_id uuid references public.women_members(id) on delete cascade,
  husband_profile_id uuid references public.profiles(id) on delete set null, full_name text);
create table public.web_relatives (id uuid primary key default gen_random_uuid(),
  man_id uuid references public.profiles(id) on delete cascade,
  child_profile_id uuid references public.profiles(id) on delete cascade,
  husband_profile_id uuid references public.profiles(id) on delete set null,
  parent_woman_id uuid references public.women_members(id) on delete cascade,
  linked_woman_id uuid references public.women_members(id) on delete set null, name text);

-- ─── دوال الهوية (نسخة الحي) ───
create or replace function public.current_profile_id() returns uuid language sql stable set search_path to 'public' as $$
  select case when auth.uid() is null then null else coalesce(
    nullif(auth.jwt()->'app_metadata'->>'profile_id', '')::uuid, auth.uid()) end; $$;
create or replace function public.current_user_role() returns text language sql stable security definer set search_path to 'public' as $$
  select case when p.status = 'active' then p.role when p.status in ('frozen','deleted') then p.status else 'pending' end
  from public.profiles p where p.id = public.current_profile_id(); $$;
create or replace function public.is_moderator() returns boolean language sql stable security definer set search_path to 'public' as $$
  select coalesce(public.current_user_role() in ('owner', 'admin', 'monitor', 'supervisor'), false); $$;
create or replace function public.my_women_node() returns uuid language sql stable security definer set search_path to 'public' as $$
  select id from public.women_members where id = auth.uid() or linked_user_id = auth.uid() limit 1; $$;

-- ─── المرآة والمزامنة (نسخة الحي) ───
create or replace function public.mirror_profile_to_women() returns trigger language plpgsql security definer set search_path to 'public' as $function$
begin
  if new.father_id is null then return new; end if;
  if new.gender is not null and lower(new.gender) <> 'male' then return new; end if;
  insert into public.women_members (id, first_name, full_name, parent_id, gender, is_deceased, birth_date, death_date,
    is_hidden_from_tree, sort_order, photo_url, avatar_url)
  values (new.id, coalesce(new.first_name, ''), coalesce(nullif(new.full_name, ''), new.first_name, ''), new.father_id, 'male',
    coalesce(new.is_deceased, false), new.birth_date, new.death_date, coalesce(new.is_hidden_from_tree, false),
    coalesce(new.sort_order, 0), new.photo_url, new.avatar_url)
  on conflict (id) do nothing;
  return new;
end; $function$;

create or replace function public.sync_profile_update_to_women() returns trigger language plpgsql security definer set search_path to 'public' as $function$
begin
  if new.father_id is not null and (new.gender is null or lower(new.gender) = 'male') then
    insert into public.women_members (id, first_name, full_name, parent_id, gender, is_deceased, birth_date, death_date,
      is_hidden_from_tree, sort_order, photo_url, avatar_url)
    values (new.id, coalesce(new.first_name, ''), coalesce(nullif(new.full_name, ''), new.first_name, ''), new.father_id, 'male',
      coalesce(new.is_deceased, false), new.birth_date, new.death_date, coalesce(new.is_hidden_from_tree, false),
      coalesce(new.sort_order, 0), new.photo_url, new.avatar_url)
    on conflict (id) do update set first_name = excluded.first_name, full_name = excluded.full_name,
      parent_id = excluded.parent_id, is_deceased = excluded.is_deceased, birth_date = excluded.birth_date,
      death_date = excluded.death_date, is_hidden_from_tree = excluded.is_hidden_from_tree;
  else
    if exists (select 1 from public.women_members w where w.husband_id = new.id or w.parent_id = new.id or w.mother_id = new.id) then
      update public.women_members set first_name = coalesce(new.first_name, ''),
        full_name = coalesce(nullif(new.full_name, ''), new.first_name, ''), is_deceased = coalesce(new.is_deceased, false),
        birth_date = new.birth_date, death_date = new.death_date, is_hidden_from_tree = coalesce(new.is_hidden_from_tree, false)
      where id = new.id;
    else
      delete from public.women_members where id = new.id;
    end if;
  end if;
  return new;
end; $function$;

create or replace function public.sync_profile_delete_to_women() returns trigger language plpgsql security definer set search_path to 'public' as $function$
begin
  delete from public.women_members where id = old.id;
  return old;
end; $function$;

create or replace function public.mirror_profile_wife_to_women(p_wife_id uuid) returns void language plpgsql security definer set search_path to 'public' as $function$
declare w public.profiles%rowtype;
begin
  select * into w from public.profiles where id = p_wife_id;
  if w.id is null or lower(coalesce(w.gender, '')) <> 'female' or w.husband_id is null then return; end if;
  insert into public.women_members (id, first_name, full_name, husband_id, gender, is_deceased, birth_date, death_date,
    sort_order, photo_url, avatar_url)
  values (w.id, coalesce(w.first_name, ''), coalesce(nullif(w.full_name, ''), w.first_name, ''),
    (select wm.id from public.women_members wm where wm.id = w.husband_id), 'female', coalesce(w.is_deceased, false),
    w.birth_date, w.death_date, coalesce(w.sort_order, 0), w.photo_url, w.avatar_url)
  on conflict (id) do nothing;
end; $function$;

create or replace function public.trg_profiles_wife_hidden_and_mirrored() returns trigger language plpgsql security definer set search_path to 'public' as $function$
begin
  if lower(coalesce(new.gender, '')) = 'female' and new.husband_id is not null and new.father_id is null then
    new.is_hidden_from_tree := true;
  end if;
  return new;
end; $function$;

create or replace function public.trg_profiles_wife_mirror_after() returns trigger language plpgsql security definer set search_path to 'public' as $function$
begin
  if lower(coalesce(new.gender, '')) = 'female' and new.husband_id is not null and new.father_id is null then
    perform public.mirror_profile_wife_to_women(new.id);
  end if;
  return new;
end; $function$;

create or replace function public.trg_profiles_protect_delete() returns trigger language plpgsql as $function$
begin
  if old.role = 'owner' and session_user not in ('postgres', 'supabase_admin') then
    raise exception 'owner_protected' using hint = 'لا يمكن حذف المالك';
  end if;
  if session_user = 'supabase_auth_admin' and exists (select 1 from auth.users u where u.id = old.id) then
    raise exception 'account_protected' using hint = 'ملف عضو مربوط بحساب دخول لا يُحذف آلياً';
  end if;
  if auth.uid() is not null then
    if old.id = auth.uid() then
      raise exception 'cannot_delete_self' using hint = 'لا يمكن حذف سجلك من لوحة الإدارة';
    end if;
  end if;
  return old;
end; $function$;

create or replace function public.prevent_role_self_promotion() returns trigger language plpgsql security definer set search_path to 'public' as $function$
declare caller_role text := coalesce(public.current_user_role(), 'anonymous'); me uuid := public.current_profile_id();
begin
  if auth.role() = 'service_role' or (auth.role() is null and session_user in ('postgres','supabase_admin','supabase_auth_admin')) then
    return new;
  end if;
  if me is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if tg_op = 'INSERT' then
    if coalesce(new.role,'pending') not in ('pending','member') then
      raise exception 'privileged_role_requires_role_management' using errcode = '42501';
    end if;
    if coalesce(new.status,'pending') <> 'pending' and caller_role not in ('owner','admin','monitor','supervisor') then
      raise exception 'approval_required' using errcode = '42501';
    end if;
    return new;
  end if;
  if caller_role in ('frozen','deleted') then raise exception 'account_inactive' using errcode = '42501'; end if;
  if old.role = 'owner' and (new.role is distinct from old.role or new.status is distinct from old.status) then
    raise exception 'owner_protected' using errcode = '42501';
  end if;
  if new.role = 'owner' and old.role is distinct from 'owner' then raise exception 'owner_protected' using errcode = '42501'; end if;
  if new.role is distinct from old.role then
    if caller_role = 'owner' and old.id <> me then null;
    elsif old.role = 'pending' and new.role = 'member' and new.status = 'active' and old.id <> me and caller_role in ('admin','monitor','supervisor') then null;
    elsif old.id = me and old.role = 'member' and new.role = 'pending' and new.status = 'pending' then null;
    else raise exception 'role_change_forbidden' using errcode = '42501';
    end if;
  end if;
  if new.status is distinct from old.status then
    if caller_role in ('owner','admin','monitor') and old.id <> me then null;
    elsif caller_role = 'supervisor' and old.id <> me and old.status = 'pending' and new.status = 'active' and new.role = 'member' then null;
    elsif old.id = me and old.status = 'active' and new.status = 'pending' and new.role = 'pending' then null;
    else raise exception 'status_change_forbidden' using errcode = '42501';
    end if;
  end if;
  return new;
end; $function$;

create or replace function public.trg_profiles_protect_sensitive_columns() returns trigger language plpgsql security definer set search_path to 'public' as $function$
declare caller_role text := coalesce(public.current_user_role(), 'anonymous'); me uuid := public.current_profile_id(); is_staff boolean;
begin
  if auth.role() = 'service_role' or (auth.role() is null and session_user in ('postgres', 'supabase_admin', 'supabase_auth_admin')) then
    return new;
  end if;
  is_staff := caller_role in ('owner', 'admin', 'monitor');
  if caller_role <> 'owner' and (new.is_admin is distinct from old.is_admin or new.is_hr_member is distinct from old.is_hr_member
      or new.hr_status is distinct from old.hr_status) then
    raise exception 'privileged_column_forbidden' using errcode = '42501';
  end if;
  if coalesce(new.is_approved, false) and not coalesce(old.is_approved, false) and caller_role not in ('owner', 'admin', 'monitor', 'supervisor') then
    raise exception 'approval_required' using errcode = '42501';
  end if;
  if old.id = me and not is_staff and coalesce(old.status, 'pending') <> 'pending' and (
       new.is_deceased is distinct from old.is_deceased or new.death_date is distinct from old.death_date
    or new.father_id is distinct from old.father_id or new.is_hidden_from_tree is distinct from old.is_hidden_from_tree
    or new.family_name is distinct from old.family_name) then
    raise exception 'self_edit_forbidden' using errcode = '42501', hint = 'هذه البيانات تتعدل عبر طلب للإدارة';
  end if;
  return new;
end; $function$;

create or replace function public.log_women_change_to_activity() returns trigger language plpgsql security definer set search_path to 'public' as $function$
declare admin_id uuid; actor uuid := auth.uid(); who text; head text; detail text; k text;
begin
  if tg_op = 'DELETE' then
    who := coalesce(nullif(old.full_name,''), old.first_name, 'عضوة'); head := 'حذف من شجرة النساء';
    detail := who || ' حُذف من شجرة النساء'; k := 'women_delete';
  elsif tg_op = 'INSERT' then
    who := coalesce(nullif(new.full_name,''), new.first_name, 'عضوة'); head := 'إضافة في شجرة النساء';
    detail := who || ' أُضيف إلى شجرة النساء'; k := 'women_add';
  else
    who := coalesce(nullif(new.full_name,''), new.first_name, 'عضوة'); detail := '';
    if new.husband_id is distinct from old.husband_id then detail := detail || 'الزوج · '; end if;
    if new.parent_id  is distinct from old.parent_id  then detail := detail || 'الأب · '; end if;
    if new.mother_id  is distinct from old.mother_id  then detail := detail || 'الأم · '; end if;
    if detail = '' then return new; end if;
    head := 'تعديل في شجرة النساء'; detail := who || ' — ' || rtrim(detail, ' · '); k := 'women_edit';
  end if;
  for admin_id in select id from public.profiles where role in ('owner','admin','monitor','supervisor') and status = 'active'
      and (actor is null or id <> actor) loop
    insert into public.notifications (target_member_id, title, body, kind, created_by, is_read) values (admin_id, head, detail, k, actor, false);
  end loop;
  return case when tg_op = 'DELETE' then old else new end;
end; $function$;

create or replace function public.remove_self_wife(p_wife_id uuid) returns void language plpgsql security definer set search_path to 'public' as $function$
declare me uuid := public.my_women_node();
begin
  if me is null then raise exception 'no_node'; end if;
  if not exists (select 1 from public.women_members where id = p_wife_id and husband_id = me) then raise exception 'not_your_wife'; end if;
  update public.women_members set husband_id = null where id = p_wife_id;
  if not exists (select 1 from public.women_members where id = p_wife_id
        and (parent_id is not null or mother_id is not null or linked_user_id is not null))
     and not exists (select 1 from public.women_members c where c.parent_id = p_wife_id or c.mother_id = p_wife_id) then
    delete from public.women_members where id = p_wife_id;
  end if;
end; $function$;

create or replace function public.move_child_gender(p_child_id uuid, p_to_gender text) returns uuid language plpgsql security definer set search_path to 'public' as $function$
declare g text := lower(coalesce(p_to_gender, '')); pr public.profiles%rowtype; wm public.women_members%rowtype; new_id uuid;
begin
  if not public.is_moderator() then raise exception 'not_authorized'; end if;
  if g = 'female' then
    select * into pr from public.profiles where id = p_child_id;
    if not found then
      update public.women_members set gender = 'female', photo_url = null, avatar_url = null where id = p_child_id;
      return p_child_id;
    end if;
    insert into public.women_members(id, first_name, full_name, parent_id, gender, is_deceased, birth_date, death_date, is_hidden_from_tree, sort_order)
    values (gen_random_uuid(), pr.first_name, coalesce(nullif(pr.full_name, ''), pr.first_name), pr.father_id, 'female',
      coalesce(pr.is_deceased, false), pr.birth_date, pr.death_date, coalesce(pr.is_hidden_from_tree, false), coalesce(pr.sort_order, 0))
    returning id into new_id;
    delete from public.profiles where id = p_child_id;
    return new_id;
  else
    return p_child_id;
  end if;
end; $function$;

-- ─── المشغّلات (كما في الحي) ───
create trigger profiles_wife_hidden before insert or update of husband_id on public.profiles
  for each row execute function public.trg_profiles_wife_hidden_and_mirrored();
create trigger profiles_wife_mirror after insert or update of husband_id on public.profiles
  for each row execute function public.trg_profiles_wife_mirror_after();
create trigger trg_mirror_profile_to_women after insert on public.profiles
  for each row execute function public.mirror_profile_to_women();
create trigger trg_prevent_role_self_promotion before insert or update on public.profiles
  for each row execute function public.prevent_role_self_promotion();
create trigger trg_profiles_protect_delete before delete on public.profiles
  for each row execute function public.trg_profiles_protect_delete();
create trigger trg_profiles_protect_sensitive_columns before update on public.profiles
  for each row execute function public.trg_profiles_protect_sensitive_columns();
create trigger trg_sync_profile_delete_to_women after delete on public.profiles
  for each row execute function public.sync_profile_delete_to_women();
create trigger trg_sync_profile_update_to_women after update on public.profiles for each row
  when ((old.father_id is distinct from new.father_id) or (old.first_name is distinct from new.first_name)
     or (old.full_name is distinct from new.full_name) or (old.gender is distinct from new.gender)
     or (old.is_deceased is distinct from new.is_deceased) or (old.birth_date is distinct from new.birth_date)
     or (old.death_date is distinct from new.death_date) or (old.is_hidden_from_tree is distinct from new.is_hidden_from_tree))
  execute function public.sync_profile_update_to_women();
create trigger trg_women_activity_log after insert or delete or update on public.women_members
  for each row execute function public.log_women_change_to_activity();
create trigger trg_women_auto_merge_wife after insert on public.women_members
  for each row execute function public.women_auto_merge_wife();
