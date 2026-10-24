-- الموافقة على شروط الاستخدام على السيرفر (طلب المالك ٢٠٢٦-١٠-٢١، الموافقة (ب): التوصية ١٥). مُعدّ ولم يُطبَّق.
-- يحتاج 20261021110000_app_config قبله (terms_version، الافتراضي ١ = نسخة التطبيقين اليوم).
--
-- اليوم الموافقة محفوظة في الجهاز فقط (iOS TermsAgreement: UserDefaults «termsAccepted.v1.<id>»، Android نفس المفتاح)،
-- ونسخة الشروط ثابتة في التطبيقين — رفعها يحتاج نسخة جديدة. الآن:
--  ١) profiles.terms_accepted_version (جديد) + profiles.terms_accepted_at (موجود منذ 20260623102733 ولا يكتبه أحد) =
--     آخر نسخة وافق عليها العضو ووقتها. المالك يرفع terms_version من صفحة الإعدادات فيُطلب من الجميع الموافقة مرة أخرى.
--  ٢) accept_terms(p_version) — لكل من له ملف (المعلّق أيضاً: يوافق عند التسجيل؛ المجمّد لا — 42501 account_inactive).
--     p_version بين ١ والنسخة الحالية (غيره 22023 bad_value). لا تنزل النسخة المحفوظة. بلا ملف ← P0002 no_profile.
--  ٣) my_terms_status() — {current_version, accepted_version, accepted_at, needs_accept} للعضو عن نفسه.
--  الكتابة من دالة SECURITY DEFINER فلا يحسبها حد تعديل الملف، ولا تغيّر دوراً أو حالة أو اسماً (حراس profiles تمر).
--
-- التراجع: supabase/rollback/20261021150000_terms_acceptance_rollback.sql (يحذف العمود الجديد ويفرّغ ما كتبته accept_terms)
-- تجربة محلية: cd supabase/tests/family_links && node terms_acceptance.test.mjs

alter table public.profiles add column terms_accepted_version integer
  check (terms_accepted_version is null or terms_accepted_version >= 1);
comment on column public.profiles.terms_accepted_version is
  'آخر نسخة من شروط الاستخدام وافق عليها العضو (تُقارن بـ app_config.terms_version) — تكتبها accept_terms()';

create function public.my_terms_status() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_cur integer := public.config_int('terms_version', 1);
  v_ver integer;
  v_at  timestamptz;
begin
  if public.current_profile_id() is null then
    raise exception 'غير مسجّل' using errcode = '42501', hint = 'not_allowed';
  end if;
  select p.terms_accepted_version, p.terms_accepted_at into v_ver, v_at
    from public.profiles p where p.id = public.current_profile_id();
  return jsonb_build_object('current_version', v_cur, 'accepted_version', v_ver, 'accepted_at', v_at,
                            'needs_accept', coalesce(v_ver, 0) < v_cur);
end;
$$;

create function public.accept_terms(p_version integer) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_me  uuid := public.current_profile_id();
  v_cur integer := public.config_int('terms_version', 1);
  v_ver integer;
  v_at  timestamptz;
begin
  if v_me is null then
    raise exception 'غير مسجّل' using errcode = '42501', hint = 'not_allowed';
  end if;
  if coalesce(public.current_user_role(), '') in ('frozen', 'deleted') then
    raise exception 'الحساب موقوف' using errcode = '42501', hint = 'account_inactive';
  end if;
  if p_version is null or p_version < 1 or p_version > v_cur then
    raise exception 'نسخة الشروط غير صحيحة (الحالية %)', v_cur using errcode = '22023', hint = 'bad_value';
  end if;
  update public.profiles p
     set terms_accepted_version = greatest(coalesce(p.terms_accepted_version, 0), p_version),
         terms_accepted_at = now()
   where p.id = v_me
  returning p.terms_accepted_version, p.terms_accepted_at into v_ver, v_at;
  if not found then
    raise exception 'لا يوجد ملف لهذا الحساب بعد' using errcode = 'P0002', hint = 'no_profile';
  end if;
  return jsonb_build_object('current_version', v_cur, 'accepted_version', v_ver, 'accepted_at', v_at,
                            'needs_accept', v_ver < v_cur);
end;
$$;

revoke all on function public.my_terms_status() from public, anon, authenticated, service_role;
grant execute on function public.my_terms_status() to authenticated;
revoke all on function public.accept_terms(integer) from public, anon, authenticated, service_role;
grant execute on function public.accept_terms(integer) to authenticated;
