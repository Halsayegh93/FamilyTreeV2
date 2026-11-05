-- حدّ أجهزة المالك (طلب المالك ٢٠٢٦-١٠-٣١): ٨ للمالك وحده، والباقون على max_devices_per_user.
-- كان السيرفر يستثني المالك بلا حد، والتطبيق يطبّق حدّ الكل عليه — الآن رقم واحد من السيرفر للاثنين.
alter table public.app_settings
  add column if not exists owner_max_devices integer not null default 8
  check (owner_max_devices between 1 and 50);

create or replace function public.trg_device_tokens_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_max integer;
  v_n   integer;
  v_owner boolean;
begin
  if coalesce(auth.role(), '') not in ('authenticated', 'anon') then
    return new;
  end if;
  perform pg_catalog.pg_advisory_xact_lock(20261021, pg_catalog.hashtext(coalesce(new.member_id::text, '')));
  -- نفس الجهاز (upsert يحدّث رمزه) — ليس جهازاً جديداً
  if new.device_id is not null and exists (select 1 from public.device_tokens d
                                            where d.member_id = new.member_id and d.device_id = new.device_id) then
    return new;
  end if;
  v_owner := exists (select 1 from public.profiles p where p.id = new.member_id and p.role = 'owner');
  select case when v_owner then a.owner_max_devices else a.max_devices_per_user end
    into v_max from public.app_settings a order by a.updated_at desc limit 1;
  v_max := coalesce(v_max, case when v_owner then 8 else 3 end);
  select count(*) into v_n from public.device_tokens d where d.member_id = new.member_id;
  if v_n >= v_max then
    raise exception 'وصلت للحد الأقصى من الأجهزة (%) — أزل جهازاً قديماً أولاً', v_max
      using errcode = 'P0001', hint = 'device_limit_reached';
  end if;
  return new;
end;
$$;
