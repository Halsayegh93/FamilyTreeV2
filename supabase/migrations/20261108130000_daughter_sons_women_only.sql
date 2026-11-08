-- ابن البنت في شجرة النساء فقط — «فرع خارج العائلة» (طلب المالك ٢٠٢٦-١١-٠٨ «ظهور ابناء البنات فقط في شجرة النساء»
--   + «ما ينحسب من اعداد العائلة… نسميهم فرع خارج العائلة»)
-- APPLIED 2026-11-08 بموافقة المالك («نعم اضفه»). جُرّب قبلها على الحي داخل كتلة تُلغى (إظهار يبقى مخفياً، الربط بأب وابن تحته مرفوضان، المسجّلون 2365→2364).
-- التراجع: supabase/rollback/20261108130000_daughter_sons_women_only_rollback.sql
--
-- حساب في `daughter_son_lineage` (قبلته الإدارة كابن بنت):
--   • يبقى مخفياً من شجرة الرجال دائماً — «إظهار» من أي مكان (تطبيق، موقع، دالة) يرجع مخفياً بصمت.
--   • لا أب له في شجرة الرجال — ربطه بأب يُرفض (hint = daughter_son_women_only)؛ أبوه وأمّه في شجرة النساء.
--   • لا أبناء تحته في شجرة الرجال — إضافة ابن أبوه ابن بنت تُرفض بالـ hint نفسه.
--   • لا يُعدّ في أرقام الاستخدام والمسجّلين (`app_usage_stats` / `app_usage_members`) — نفس الدالتين بشرط واحد زائد.
-- لا يفكّ أي رابط موجود ولا يلمس شجرة النساء. إخراجه من النسب = حذف صفّه من `daughter_son_lineage` (صيانة SQL).

create or replace function private.daughter_son_women_only()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  if exists (select 1 from public.daughter_son_lineage d where d.profile_id = new.id) then
    new.is_hidden_from_tree := true;
    if new.father_id is not null
       and (tg_op = 'INSERT' or new.father_id is distinct from old.father_id) then
      raise exception 'ابن البنت في شجرة النساء فقط — لا يُربط بأب في شجرة العائلة'
        using errcode = 'P0001', hint = 'daughter_son_women_only';
    end if;
  end if;
  if new.father_id is not null
     and (tg_op = 'INSERT' or new.father_id is distinct from old.father_id)
     and exists (select 1 from public.daughter_son_lineage d where d.profile_id = new.father_id) then
    raise exception 'أبناء ابن البنت في شجرة النساء — لا يُضافون تحته في شجرة العائلة'
      using errcode = 'P0001', hint = 'daughter_son_women_only';
  end if;
  return new;
end;
$function$;

revoke all on function private.daughter_son_women_only() from public, anon, authenticated;

drop trigger if exists trg_daughter_son_women_only on public.profiles;
create trigger trg_daughter_son_women_only
  before insert or update of father_id, is_hidden_from_tree on public.profiles
  for each row execute function private.daughter_son_women_only();

-- ── أرقام الاستخدام والمسجّلين بلا «فرع خارج العائلة» ──
create or replace function public.app_usage_stats()
 returns table(active integer, idle integer, login_no_device integer, never_logged integer, no_phone integer)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  with alive as (
    select p.id, nullif(trim(p.phone_number), '') is not null as has_phone
    from public.profiles p
    where coalesce(p.is_deceased, false) = false and p.role <> 'pending'
      -- «فرع خارج العائلة» (أبناء البنات) لا يُعدّون في أرقام العائلة
      and not exists (select 1 from public.daughter_son_lineage d where d.profile_id = p.id)
  ), act as (
    select a.id, a.has_phone,
      exists (select 1 from public.device_tokens d where d.member_id = a.id) as has_device,
      u.id is not null as has_login,
      greatest(u.last_sign_in_at,
               (select max(d.updated_at) from public.device_tokens d where d.member_id = a.id)) as last_seen
    from alive a
    left join auth.users u on u.id = a.id
  )
  select
    (count(*) filter (where has_phone and has_device and last_seen >= now() - interval '21 days'))::int,
    (count(*) filter (where has_phone and has_device and (last_seen < now() - interval '21 days' or last_seen is null)))::int,
    (count(*) filter (where has_phone and has_login and not has_device))::int,
    (count(*) filter (where has_phone and not has_login and not has_device))::int,
    (count(*) filter (where not has_phone))::int
  from act
  where public.is_moderator();
$function$;

create or replace function public.app_usage_members(p_category text)
 returns table(member_id uuid, full_name text, phone text, last_seen timestamp with time zone, account_created timestamp with time zone, has_login boolean)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  with alive as (
    select p.id, p.full_name, p.phone_number,
           nullif(trim(p.phone_number), '') is not null as has_phone
    from public.profiles p
    where coalesce(p.is_deceased, false) = false and p.role <> 'pending'
      -- «فرع خارج العائلة» (أبناء البنات) لا يُعدّون في أرقام العائلة
      and not exists (select 1 from public.daughter_son_lineage d where d.profile_id = p.id)
  ), act as (
    select a.*,
      exists (select 1 from public.device_tokens d where d.member_id = a.id) as has_device,
      u.id is not null as has_login,
      u.created_at as account_created,
      greatest(u.last_sign_in_at,
               (select max(d.updated_at) from public.device_tokens d where d.member_id = a.id)) as last_seen
    from alive a
    left join auth.users u on u.id = a.id
  ), cat as (
    select act.*,
      case
        when not has_phone then 'no_phone'
        when has_device and last_seen >= now() - interval '21 days' then 'active'
        when has_device then 'idle'
        when has_login then 'login_no_device'
        else 'never_logged'
      end as category
    from act
  )
  select id, full_name, phone_number, last_seen, account_created, has_login
  from cat
  where category = p_category and public.is_moderator()
  order by last_seen desc nulls last, full_name;
$function$;
