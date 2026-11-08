-- «طلب نسب» كامل للإدارة (طلب المالك ٢٠٢٦-١١-٠٨، فوق 20261107120000 و20261108090000):
-- «الارسال يصل للادارة الطلب كامل: اسمه و اسم امه و جده لمعرفته و رقم هاتفه و منو سجل … ومن اي جهاز سجل انضمامه».
-- NOT APPLIED — يُطبَّق بموافقة المالك. التطبيقات ترجع لبطاقة اليوم إن غابت الدالة.
--
-- lineage_request_details(p_request_id) → jsonb، للمالك والمدير والمراقب فقط (current_user_role)، قراءة فقط:
--   member   — اسمه الكامل، رقمه كاملاً (الثلاثة من «الفريق»: نفس قاعدة members_masked)، متى سجّل، منصة التسجيل.
--   mother   — بنت من العائلة: اسمها + سلسلتها (هي · أبوها · جدها · أبو جدها) من شجرة النساء/الرجال؛
--              أو «أم جديدة»: الاسم المكتوب + سلسلة أبيها المختار من شجرة الرجال.
--   father   — زوجها المسجّل أو الاسم المكتوب سطراً واحداً، حي/متوفى.
--   requester / join — من أرسل طلب النسب ومن أرسل طلب الانضمام ومن ردّ عليه؛ lineage — من وافق عليه «ابن بنت» ومتى.
--   devices  — أجهزته من device_tokens (الأقدم أولاً، ١٠ بحد أقصى) + first_device + device_count.
-- التراجع: rollback/20261108120000_lineage_request_details_rollback.sql
-- تجربة: cd supabase/tests/family_links && node lineage_request_details.test.mjs

create or replace function public.lineage_request_details(p_request_id uuid)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  r      public.admin_requests%rowtype;
  d      jsonb;
  son    public.profiles%rowtype;
  mom    public.women_members%rowtype;
  dad    public.women_members%rowtype;
  l      public.daughter_son_lineage%rowtype;
  is_new boolean;
  f_id   uuid;   -- أبو الأم
  g_id   uuid;   -- جدها
  gg_id  uuid;   -- أبو جدها
  m_name text;
  m_first text;
  chain  jsonb;
  mother jsonb;
  father jsonb;
  jr     public.admin_requests%rowtype;
  devs   jsonb;
begin
  if coalesce(public.current_user_role(), '') not in ('owner', 'admin', 'monitor') then
    raise exception 'طلبات النسب للمالك والمدير والمراقب' using errcode = '42501', hint = 'not_allowed';
  end if;
  select * into r from public.admin_requests where id = p_request_id;
  if not found or r.request_type is distinct from 'lineage_request' then
    raise exception 'الطلب غير موجود' using errcode = 'P0001', hint = 'request_not_found';
  end if;
  begin
    d := r.details::jsonb;
  exception when others then
    d := null;
  end;
  if d is null or jsonb_typeof(d) <> 'object' then
    d := '{}'::jsonb;
  end if;

  select * into son from public.profiles where id = coalesce(r.member_id, r.requester_id);
  select * into l from public.daughter_son_lineage where profile_id = son.id;

  -- ── الأم وسلسلتها ──
  is_new := coalesce(coalesce(d->>'mother_id', '') = '' and jsonb_typeof(d->'new_mother') = 'object', false);
  if is_new then
    m_name := btrim(coalesce(d->'new_mother'->>'name', d->>'mother_name', ''));
    m_first := coalesce(nullif(btrim(d->'new_mother'->>'first_name'), ''), split_part(m_name, ' ', 1));
    begin
      f_id := nullif(d->'new_mother'->>'father_id', '')::uuid;
    exception when others then
      f_id := null;
    end;
  elsif coalesce(d->>'mother_id', '') <> '' then
    begin
      select * into mom from public.women_members where id = (d->>'mother_id')::uuid;
    exception when others then
      mom := null;
    end;
    m_name := coalesce(nullif(btrim(mom.full_name), ''), nullif(btrim(mom.first_name), ''), btrim(coalesce(d->>'mother_name', '')));
    m_first := coalesce(nullif(btrim(mom.first_name), ''), split_part(m_name, ' ', 1));
    f_id := mom.parent_id;
  end if;
  -- الرجال: ملف شجرة الرجال أولاً (نفس المعرّف في شجرة النساء)، ثم عقدة شجرة النساء
  if f_id is not null then
    g_id := coalesce((select p.father_id from public.profiles p where p.id = f_id),
                     (select w.parent_id from public.women_members w where w.id = f_id));
  end if;
  if g_id is not null then
    gg_id := coalesce((select p.father_id from public.profiles p where p.id = g_id),
                      (select w.parent_id from public.women_members w where w.id = g_id));
  end if;
  select coalesce(jsonb_agg(x.v order by x.o), '[]'::jsonb) into chain
    from (select 0 o, to_jsonb(nullif(m_first, '')) v
          union all
          select k.o, to_jsonb(coalesce(
                   (select nullif(btrim(p.first_name), '') from public.profiles p where p.id = k.id),
                   (select nullif(btrim(w.first_name), '') from public.women_members w where w.id = k.id)))
            from (values (1, f_id), (2, g_id), (3, gg_id)) k(o, id)
           where k.id is not null) x
   where x.v is not null and x.v <> 'null'::jsonb;

  mother := jsonb_build_object(
    'is_new', is_new,
    'id', case when is_new then null else mom.id end,
    'name', nullif(m_name, ''),
    'first_name', nullif(m_first, ''),
    'is_deceased', case when is_new then coalesce((d->'new_mother'->>'is_deceased')::boolean, false)
                        else mom.is_deceased end,
    'chain', chain,
    'father', case when f_id is null then null else jsonb_build_object('id', f_id, 'name', coalesce(
                (select coalesce(nullif(btrim(p.full_name), ''), p.first_name) from public.profiles p where p.id = f_id),
                (select coalesce(nullif(btrim(w.full_name), ''), w.first_name) from public.women_members w where w.id = f_id),
                d->'new_mother'->>'father_name')) end,
    'grandfather', case when g_id is null then null else jsonb_build_object('id', g_id, 'name', coalesce(
                (select coalesce(nullif(btrim(p.full_name), ''), p.first_name) from public.profiles p where p.id = g_id),
                (select coalesce(nullif(btrim(w.full_name), ''), w.first_name) from public.women_members w where w.id = g_id))) end);

  -- ── الأب ──
  if coalesce(d->>'father_id', '') <> '' then
    begin
      select * into dad from public.women_members where id = (d->>'father_id')::uuid;
    exception when others then
      dad := null;
    end;
    father := jsonb_build_object(
      'registered', true,
      'id', d->>'father_id',
      'name', coalesce(nullif(btrim(dad.full_name), ''), nullif(btrim(dad.first_name), ''), d->>'father_name'),
      'is_deceased', coalesce(dad.is_deceased, (d->>'father_is_deceased')::boolean),
      'is_outside_family', coalesce(dad.is_outside_family, false));
  else
    father := jsonb_build_object(
      'registered', false,
      'id', null,
      'name', coalesce(nullif(btrim(d->>'father_name'), ''), nullif(btrim(d->'father'->>'full_name'), '')),
      'is_deceased', coalesce((d->>'father_is_deceased')::boolean, (d->'father'->>'is_deceased')::boolean, false),
      'is_outside_family', true);
  end if;

  -- ── طلب الانضمام (من أرسله ومن ردّ عليه) ──
  select * into jr from public.admin_requests j
   where j.member_id = son.id and j.request_type in ('join_request', 'link_request')
   order by j.created_at asc nulls last
   limit 1;

  -- ── الأجهزة: الأقدم أولاً ──
  select coalesce(jsonb_agg(jsonb_build_object(
           'platform', t.platform, 'device_name', t.device_name, 'app_version', t.app_version,
           'app_build', t.app_build, 'created_at', t.created_at, 'updated_at', t.updated_at)
           order by t.created_at asc nulls last, t.id), '[]'::jsonb)
    into devs
    from (select * from public.device_tokens x where x.member_id = son.id
           order by x.created_at asc nulls last, x.id limit 10) t;

  return jsonb_build_object(
    'v', 1,
    'request', jsonb_build_object('id', r.id, 'status', r.status, 'created_at', r.created_at,
                                  'summary', d->>'summary'),
    'member', case when son.id is null then null else jsonb_build_object(
                'id', son.id,
                'full_name', coalesce(nullif(btrim(son.full_name), ''), son.first_name),
                'phone', son.phone_number,
                'phone_hidden', coalesce(son.is_phone_hidden, false),
                'registered_at', son.created_at,
                'registration_platform', son.registration_platform,
                'status', son.status) end,
    'mother', mother,
    'father', father,
    'requester', case when r.requester_id is null then null else jsonb_build_object(
                'id', r.requester_id,
                'name', (select coalesce(nullif(btrim(p.full_name), ''), p.first_name) from public.profiles p where p.id = r.requester_id),
                'is_self', r.requester_id = son.id) end,
    'join', case when jr.id is null then null else jsonb_build_object(
                'id', jr.id, 'type', jr.request_type, 'status', jr.status, 'created_at', jr.created_at,
                'requester', case when jr.requester_id is null then null else jsonb_build_object(
                  'id', jr.requester_id,
                  'name', (select coalesce(nullif(btrim(p.full_name), ''), p.first_name) from public.profiles p where p.id = jr.requester_id),
                  'is_self', jr.requester_id = son.id) end,
                'replied_by', case when jr.replied_by is null then null else jsonb_build_object(
                  'id', jr.replied_by,
                  'name', (select coalesce(nullif(btrim(p.full_name), ''), p.first_name) from public.profiles p where p.id = jr.replied_by)) end,
                'replied_at', jr.replied_at) end,
    'lineage', case when l.profile_id is null then null else jsonb_build_object(
                'approved_at', l.approved_at,
                'completed_at', l.completed_at,
                'approved_by', case when l.approved_by is null then null else jsonb_build_object(
                  'id', l.approved_by,
                  'name', (select coalesce(nullif(btrim(p.full_name), ''), p.first_name) from public.profiles p where p.id = l.approved_by),
                  'role', (select p.role from public.profiles p where p.id = l.approved_by)) end) end,
    'devices', devs,
    'first_device', devs->0,
    'device_count', (select count(*) from public.device_tokens x where x.member_id = son.id));
end;
$function$;

revoke all on function public.lineage_request_details(uuid) from public, anon;
grant execute on function public.lineage_request_details(uuid) to authenticated;
