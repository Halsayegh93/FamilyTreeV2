-- حارسان من السيرفر لإعدادين يقرؤهما التطبيق وحده اليوم (طلب المالك ٢٠٢٦-١٠-٢١، الموافقة (أ): الخللان ١ و٥).
-- مُعدّ ولم يُطبَّق. لا يحتاج 20261021110000 (يقرأ app_settings مباشرة).
--
--  ١) «السماح بالتسجيل» (app_settings.allow_new_registrations): كان يُكتب من التطبيقين ولا يقرؤه أحد. الآن إذا أُطفئ:
--     • profiles: جلسة التطبيق (JWT authenticated/anon) لغير الإدارة الأربعة ترفض على سجلها هو (المعرّف = current_profile_id
--       أو auth.uid): إدراج سجل جديد، أو تحويله إلى «مسجّل» (role ← pending)، أو كتابة اسم على السجل المبدئي الفارغ وهو معلّق
--       = بالضبط ما يكتبه نموذج التسجيل في iOS (registerNewUser) وAndroid (registration_screen _submit).
--     • admin_requests: طلب انضمام/ربط (join_request / link_request) من غير الإدارة لعضو «مسجّل» (role = pending) أو بلا اسم
--       أو بلا ملف — يُرفض (يغطي النسخ القديمة التي ترسل الطلب مباشرة).
--     الخطأ: P0001 برسالة عربية و hint = registrations_closed.
--     لا يمسّ: عضو الشجرة الذي يدخل لأول مرة (handle_new_user_by_phone/adopt_tree_profile من محفّز Auth)، ولا طلب انضمام
--     عضو شجرة قائم (role member باسمه — «موجود في الشجرة، الموافقة تفعّله»)، ولا المالك/المدير/المراقب/المشرف وهم يضيفون
--     أعضاء، ولا دخول الأعضاء المفعّلين، ولا الخدمة وصيانة SQL. مفتوح (الافتراضي) = لا تغيير إطلاقاً.
--  ٢) حد الأجهزة (app_settings.max_devices_per_user، احتياطي ٣ كما في التطبيقين): device_tokens قبل الإدراج — جهاز جديد
--     (لا صف بنفس member_id + device_id) وعدد أجهزة العضو بلغ الحد ← P0001 hint = device_limit_reached. تحديث جهاز مسجّل
--     (upsert على member_id,device_id) يمر دائماً. المالك مستثنى (ملفه أو جلسته). الخدمة والصيانة تمر. قفل استشاري لكل عضو
--     يمنع جهازين متزامنين من تجاوز الحد.
--  ٣) قيد check (١..١٠) على max_devices_per_user (مدى الشاشتين) — يُضاف فقط إن كانت القيمة الحية ضمنه، وإلا يُترك مع تنبيه
--     (لا تغيير بيانات بلا موافقة).
--
-- التراجع: supabase/rollback/20261021130000_registration_and_device_guards_rollback.sql
-- تجربة محلية: cd supabase/tests/family_links && node registration_device_guards.test.mjs

-- ═══ ١-أ) التسجيل: الملف الشخصي ═══
create function public.trg_profiles_registration_gate() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_open boolean;
  v_role text;
begin
  -- جلسات التطبيقات فقط — الخدمة ومحفّز الدخول وصيانة SQL تمر
  if coalesce(auth.role(), '') not in ('authenticated', 'anon') then
    return new;
  end if;
  select a.allow_new_registrations into v_open from public.app_settings a order by a.updated_at desc limit 1;
  if coalesce(v_open, true) then
    return new;
  end if;
  v_role := coalesce(public.current_user_role(), '');
  if v_role in ('owner', 'admin', 'monitor', 'supervisor') then
    return new;
  end if;
  -- سجل غيره: ليس تسجيلاً (RLS والحراس الأخرى تقرر)
  if new.id is distinct from public.current_profile_id() and new.id is distinct from auth.uid() then
    return new;
  end if;
  if tg_op = 'INSERT'
     or (coalesce(new.role, '') = 'pending' and coalesce(old.role, '') <> 'pending')
     or (coalesce(new.status, 'pending') = 'pending'
         and btrim(coalesce(old.full_name, '')) = '' and btrim(coalesce(new.full_name, '')) <> '') then
    raise exception 'التسجيل الجديد مغلق حالياً — تواصل مع إدارة العائلة'
      using errcode = 'P0001', hint = 'registrations_closed';
  end if;
  return new;
end;
$$;
revoke all on function public.trg_profiles_registration_gate() from public, anon, authenticated, service_role;
create trigger trg_profiles_registration_gate before insert or update of role, status, full_name on public.profiles
  for each row execute function public.trg_profiles_registration_gate();

-- ═══ ١-ب) التسجيل: طلب الانضمام ═══
create function public.trg_admin_requests_registration_gate() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_open boolean;
  v_role text;
  v_p_role text;
  v_p_name text;
begin
  if coalesce(new.request_type, '') not in ('join_request', 'link_request') then
    return new;
  end if;
  if coalesce(auth.role(), '') not in ('authenticated', 'anon') then
    return new;
  end if;
  select a.allow_new_registrations into v_open from public.app_settings a order by a.updated_at desc limit 1;
  if coalesce(v_open, true) then
    return new;
  end if;
  v_role := coalesce(public.current_user_role(), '');
  if v_role in ('owner', 'admin', 'monitor', 'supervisor') then
    return new;
  end if;
  select p.role, p.full_name into v_p_role, v_p_name from public.profiles p where p.id = new.member_id;
  -- عضو شجرة قائم (باسمه ودوره ليس «مسجّل») يكمل انضمامه حتى والتسجيل مغلق
  if not found or coalesce(v_p_role, '') = 'pending' or btrim(coalesce(v_p_name, '')) = '' then
    raise exception 'التسجيل الجديد مغلق حالياً — تواصل مع إدارة العائلة'
      using errcode = 'P0001', hint = 'registrations_closed';
  end if;
  return new;
end;
$$;
revoke all on function public.trg_admin_requests_registration_gate() from public, anon, authenticated, service_role;
create trigger trg_admin_requests_registration_gate before insert on public.admin_requests
  for each row execute function public.trg_admin_requests_registration_gate();

-- ═══ ٢) حد الأجهزة ═══
create function public.trg_device_tokens_limit() returns trigger
language plpgsql security definer set search_path = '' as $$
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
  -- نفس الجهاز (upsert يحدّث رمزه) — ليس جهازاً جديداً
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
revoke all on function public.trg_device_tokens_limit() from public, anon, authenticated, service_role;
create trigger trg_device_tokens_limit before insert on public.device_tokens
  for each row execute function public.trg_device_tokens_limit();

-- ═══ ٣) قيد ١..١٠ على عدد الأجهزة (فقط إن كانت القيم الحالية ضمنه) ═══
do $$
begin
  if exists (select 1 from pg_constraint where conname = 'app_settings_max_devices_per_user_check') then
    raise notice 'app_settings_max_devices_per_user_check موجود — لم يُغيَّر';
  elsif exists (select 1 from public.app_settings where max_devices_per_user is null or max_devices_per_user not between 1 and 10) then
    raise notice 'max_devices_per_user خارج ١..١٠ في سطر الإعدادات — القيد لم يُضف. عدّل القيمة من التطبيق ثم أعد هذه الخطوة.';
  else
    alter table public.app_settings add constraint app_settings_max_devices_per_user_check
      check (max_devices_per_user between 1 and 10);
    -- علامة للتراجع: يحذف القيد فقط إن كان هذا الترحيل من أضافه
    comment on constraint app_settings_max_devices_per_user_check on public.app_settings is 'added by 20261021130000';
  end if;
end $$;
