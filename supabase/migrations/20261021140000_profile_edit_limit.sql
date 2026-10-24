-- حد تعديل الملف الشخصي من السيرفر (طلب المالك ٢٠٢٦-١٠-٢١، الموافقة (أ): الخلل ٤). مُعدّ ولم يُطبَّق.
-- يحتاج 20261021110000_app_config قبله (profile_free_edits = ٣، profile_edit_limit_enabled = تشغيل).
--
-- اليوم العدّاد في جهاز العضو (iOS ProfileEditCooldown: Keychain/UserDefaults، Android ProfileEditLimit: SharedPreferences)،
-- وزرّا المالك «إيقاف العداد» و«تصفير العداد» يؤثران على جهازه وحده. القاعدة نفسها، لكن على السيرفر:
--  • أول N تعديلات لكل حقل تُحفظ مباشرة، والتعديل N+1 يُرفض (P0001، hint = edit_limit_reached، detail = الحقول
--    مفصولة بفاصلة) فيرجع التطبيق لـ «طلب تعديل» للإدارة كما يفعل اليوم. كل حقل مستقل، والعدّاد لا يُصفَّر وحده.
--  • «تعديل» = حفظ غيّر قيمة الحقل فعلاً (كما يعدّ التطبيقان: يكتبان المتغيّر فقط ويعدّان بعد نجاح الحفظ). الحقول:
--      birthDate = birth_date · isMarried = is_married · bio = bio_json · avatar = avatar_url (رفع/استبدال؛ الحذف إلى
--      null مجاني كما في التطبيقين) · phoneNumber = phone_number (بعد تطبيعه بـ profiles_0_normalize_phone).
--    «إخفاء الرقم» (is_phone_hidden) خارج الحد: يتغيّر أيضاً من مفتاح الخصوصية في الإعدادات بلا حد (iOS SettingsView)،
--    والأندرويد لا يحدّه — فالسيرفر لا يقدر يفرّق؛ تبقى الخصوصية مجانية (قرار للمالك في SPEC.md).
--  • يُحسب على: كتابة التطبيق المباشرة (current_user = authenticated) من العضو على سجله هو، ودوره عضو أو مشرف.
--    لا يُحسب: المالك/المدير/المراقب (يعدّلون أي ملف من أدوات الإدارة أصلاً)، المعلّق (التسجيل و«تعديل البيانات»)، تعديل
--    الإدارة لملف غيرها، دوال السيرفر SECURITY DEFINER (قرار الطلبات، النقل، الحذف…)، الخدمة والصيانة.
--  • profile_edit_limit_enabled = إيقاف ← لا عدّ ولا رفض (مثل isDisabled: التعديل وقتها لا يُحسب).
--  • عدّاد جديد من الصفر للجميع عند التطبيق (عدّادات الأجهزة لا تُنقل).
--
--  ١) public.profile_edit_counts (member_id، field، edits، last_edit_at) — لا قراءة ولا كتابة من التطبيقات.
--  ٢) trg_profiles_self_edit_limit (SECURITY INVOKER — يرى من يكتب فعلاً) ← profile_edit_limit_consume (SECURITY DEFINER،
--     لا تُنادى إلا من داخل محفّز: pg_trigger_depth ≥ ١) يعدّ ويرفض ذرّياً (insert … on conflict … where edits < N).
--  ٣) profile_edit_limits(p_member_id default null) — للعضو عن نفسه (والمالك/المدير عن أي عضو):
--     {member_id, enabled, free_edits, exempt, fields: {birthDate: {used, remaining, last_edit_at}, …}}.
--  ٤) reset_profile_edit_counts(p_member_id default null, p_field default null) — المالك/المدير لعضو (كل حقوله أو حقل)،
--     والمالك وحده للجميع (p_member_id = null = «تصفير العداد»). يرجع عدد العدّادات المحذوفة.
--
-- التراجع: supabase/rollback/20261021140000_profile_edit_limit_rollback.sql
-- تجربة محلية: cd supabase/tests/family_links && node profile_edit_limit.test.mjs

-- ═══ ١) العدّاد ═══
create table public.profile_edit_counts (
  member_id    uuid not null references public.profiles(id) on delete cascade,
  field        text not null check (field in ('birthDate', 'isMarried', 'bio', 'avatar', 'phoneNumber')),
  edits        integer not null default 0 check (edits >= 0),
  last_edit_at timestamptz,
  primary key (member_id, field)
);
comment on table public.profile_edit_counts is
  'حد تعديل الملف: كم مرة عدّل العضو كل حقل مباشرة — يكتبه المحفّز فقط، ويقرؤه profile_edit_limits()';
alter table public.profile_edit_counts enable row level security;
revoke all on public.profile_edit_counts from public, anon, authenticated, service_role;

-- ═══ ٢-أ) العدّ والرفض (من المحفّز فقط) ═══
create function public.profile_edit_limit_consume(p_member uuid, p_fields text[]) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_free integer;
  v_f    text;
  v_n    integer;
  v_over text[] := '{}';
begin
  -- نداء مباشر من التطبيق (RPC) = عمق المحفّزات صفر ← مرفوض
  if pg_catalog.pg_trigger_depth() < 1 then
    raise exception 'internal' using errcode = '42501', hint = 'not_allowed';
  end if;
  if p_member is null or p_member is distinct from public.current_profile_id() then
    return;
  end if;
  if coalesce(public.current_user_role(), '') not in ('member', 'supervisor') then
    return;
  end if;
  if not public.config_bool('profile_edit_limit_enabled', true) then
    return;
  end if;
  v_free := greatest(public.config_int('profile_free_edits', 3), 0);
  foreach v_f in array p_fields loop
    v_n := null;
    insert into public.profile_edit_counts as c (member_id, field, edits, last_edit_at)
    values (p_member, v_f, 1, now())
    on conflict (member_id, field) do update
      set edits = c.edits + 1, last_edit_at = now()
      where c.edits < v_free
    returning c.edits into v_n;
    -- لا صف راجع = بلغ الحد؛ أو أول تعديل والحد صفر
    if v_n is null or v_n > v_free then
      v_over := array_append(v_over, v_f);
    end if;
  end loop;
  if cardinality(v_over) > 0 then
    raise exception 'بلغت حد التعديلات المباشرة — يُرسل التعديل للإدارة'
      using errcode = 'P0001', hint = 'edit_limit_reached', detail = array_to_string(v_over, ',');
  end if;
end;
$$;
revoke all on function public.profile_edit_limit_consume(uuid, text[]) from public, anon, authenticated, service_role;
-- المحفّز SECURITY INVOKER ينادِيها بدور الكاتب (authenticated)؛ النداء المباشر يرفضه فحص pg_trigger_depth
grant execute on function public.profile_edit_limit_consume(uuid, text[]) to authenticated;

-- ═══ ٢-ب) المحفّز (SECURITY INVOKER: current_user = من يكتب — authenticated من التطبيق، صاحب الدالة من دوال السيرفر) ═══
create function public.trg_profiles_self_edit_limit() returns trigger
language plpgsql set search_path = '' as $$
declare
  v_fields text[] := '{}';
begin
  if current_user <> 'authenticated' then
    return new;
  end if;
  if new.birth_date is distinct from old.birth_date then
    v_fields := array_append(v_fields, 'birthDate');
  end if;
  if coalesce(new.is_married, false) is distinct from coalesce(old.is_married, false) then
    v_fields := array_append(v_fields, 'isMarried');
  end if;
  if new.bio_json is distinct from old.bio_json then
    v_fields := array_append(v_fields, 'bio');
  end if;
  if new.avatar_url is not null and new.avatar_url is distinct from old.avatar_url then
    v_fields := array_append(v_fields, 'avatar');
  end if;
  if new.phone_number is distinct from old.phone_number then
    v_fields := array_append(v_fields, 'phoneNumber');
  end if;
  if cardinality(v_fields) > 0 then
    perform public.profile_edit_limit_consume(new.id, v_fields);
  end if;
  return new;
end;
$$;
revoke all on function public.trg_profiles_self_edit_limit() from public, anon, authenticated, service_role;
create trigger trg_profiles_self_edit_limit
  before update of birth_date, is_married, bio_json, avatar_url, phone_number on public.profiles
  for each row execute function public.trg_profiles_self_edit_limit();

-- ═══ ٣) القراءة ═══
create function public.profile_edit_limits(p_member_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_me     uuid := public.current_profile_id();
  v_role   text := coalesce(public.current_user_role(), '');
  v_target uuid := coalesce(p_member_id, public.current_profile_id());
  v_t_role text;
  v_free   integer := greatest(public.config_int('profile_free_edits', 3), 0);
  v_on     boolean := public.config_bool('profile_edit_limit_enabled', true);
begin
  if v_target is null then
    raise exception 'غير مسجّل' using errcode = '42501', hint = 'not_allowed';
  end if;
  if v_target is distinct from v_me and v_role not in ('owner', 'admin') then
    raise exception 'عدّادات غيرك للمالك والمدير فقط' using errcode = '42501', hint = 'not_allowed';
  end if;
  select case when p.status = 'active' then p.role when p.status in ('frozen', 'deleted') then p.status else 'pending' end
    into v_t_role from public.profiles p where p.id = v_target;
  return jsonb_build_object(
    'member_id', v_target,
    'enabled', v_on,
    'free_edits', v_free,
    'exempt', coalesce(v_t_role, '') not in ('member', 'supervisor'),
    'fields', (select jsonb_object_agg(f.field, jsonb_build_object(
                        'used', coalesce(c.edits, 0),
                        'remaining', greatest(v_free - coalesce(c.edits, 0), 0),
                        'last_edit_at', c.last_edit_at))
                 from unnest(array['birthDate', 'isMarried', 'bio', 'avatar', 'phoneNumber']) as f(field)
                 left join public.profile_edit_counts c on c.member_id = v_target and c.field = f.field));
end;
$$;
revoke all on function public.profile_edit_limits(uuid) from public, anon, authenticated, service_role;
grant execute on function public.profile_edit_limits(uuid) to authenticated;

-- ═══ ٤) التصفير ═══
create function public.reset_profile_edit_counts(p_member_id uuid default null, p_field text default null) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_role text := coalesce(public.current_user_role(), '');
  v_n    integer;
begin
  if v_role not in ('owner', 'admin') or (p_member_id is null and v_role <> 'owner') then
    raise exception 'تصفير العدّاد للمالك (والمدير لعضو واحد)' using errcode = '42501', hint = 'not_allowed';
  end if;
  if p_field is not null and p_field not in ('birthDate', 'isMarried', 'bio', 'avatar', 'phoneNumber') then
    raise exception 'حقل غير معروف: %', p_field using errcode = '22023', hint = 'bad_value';
  end if;
  delete from public.profile_edit_counts c
   where (p_member_id is null or c.member_id = p_member_id)
     and (p_field is null or c.field = p_field);
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
revoke all on function public.reset_profile_edit_counts(uuid, text) from public, anon, authenticated, service_role;
grant execute on function public.reset_profile_edit_counts(uuid, text) to authenticated;
