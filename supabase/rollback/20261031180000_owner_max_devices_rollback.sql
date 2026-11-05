-- رجوع: المالك بلا حد في السيرفر كما كان، وحذف العمود
create or replace function public.trg_device_tokens_limit()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_max integer;
  v_n   integer;
begin
  if coalesce(auth.role(), '') not in ('authenticated', 'anon') then
    return new;
  end if;
  if coalesce(public.current_user_role(), '') = 'owner'
     or exists (select 1 from public.profiles p where p.id = new.member_id and p.role = 'owner') then
    return new;
  end if;
  perform pg_catalog.pg_advisory_xact_lock(20261021, pg_catalog.hashtext(coalesce(new.member_id::text, '')));
  if new.device_id is not null and exists (select 1 from public.device_tokens d
                                            where d.member_id = new.member_id and d.device_id = new.device_id) then
    return new;
  end if;
  select a.max_devices_per_user into v_max from public.app_settings a order by a.updated_at desc limit 1;
  v_max := coalesce(v_max, 3);
  select count(*) into v_n from public.device_tokens d where d.member_id = new.member_id;
  if v_n >= v_max then
    raise exception 'وصلت للحد الأقصى من الأجهزة (%) — أزل جهازاً قديماً أولاً', v_max
      using errcode = 'P0001', hint = 'device_limit_reached';
  end if;
  return new;
end;
$$;
alter table public.app_settings drop column if exists owner_max_devices;
