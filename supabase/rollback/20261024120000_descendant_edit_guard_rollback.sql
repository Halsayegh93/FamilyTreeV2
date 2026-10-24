-- تراجع 20261024120000_descendant_edit_guard — يرجع الحال كما كان (لا حارس على تعديل سجل القريب)
drop trigger if exists trg_profiles_descendant_guard on public.profiles;
drop function if exists public.trg_profiles_descendant_guard();
drop function if exists public.profile_has_login(uuid);
