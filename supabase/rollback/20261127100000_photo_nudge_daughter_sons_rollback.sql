-- تراجع 20261127100000_photo_nudge_daughter_sons — يرجع private.photo_nudge_listed كما طُبِّقت في
-- 20261126200000_photo_requests_fixes (حرفياً، = الحي قبل الترحيل): ابن البنت (daughter_son_lineage) خارج القاعدة من جديد.
-- البيانات: الطلبات والإشعارات التي وصلت أبناء البنات تبقى كما هي (طلبهم المفتوح يُذكَّر كما كان — التذكير لا يستثنيهم).

create or replace function private.photo_nudge_listed(p_member uuid, p_me uuid, p_role text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1 from public.profiles p
     where p.id = p_member
       and p.id is distinct from p_me
       and not coalesce(p.is_deceased, false)
       and p.status = 'active'
       and coalesce(p.role, '') <> 'pending'
       and (coalesce(p.role, '') <> 'owner' or p_role = 'owner')
       and lower(coalesce(p.gender, '')) <> 'female'
       and nullif(btrim(coalesce(p.avatar_url, '')), '') is null
       and nullif(btrim(coalesce(p.photo_url, '')), '') is null
       and nullif(btrim(coalesce(p.phone_number, '')), '') is not null
       and not exists (select 1 from public.daughter_son_lineage d where d.profile_id = p.id)
       and (public.profile_has_login(p.id)
            or exists (select 1 from public.device_tokens t where t.member_id = p.id)));
$function$;

revoke all on function private.photo_nudge_listed(uuid, uuid, text) from public, anon, authenticated;
