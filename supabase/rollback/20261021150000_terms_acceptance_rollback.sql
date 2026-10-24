-- تراجع 20261021150000_terms_acceptance: يحذف الدالتين والعمود profiles.terms_accepted_version (النسخ المحفوظة تُفقد)،
-- ويعيد profiles.terms_accepted_at فارغاً لمن كتبته accept_terms (العمود قديم ولم يكن يكتبه أحد قبلها) — فتعود الحالة كما كانت.
-- طبّقه قبل تراجع 20261021110000_app_config. يعمل على قاعدة لم يُطبَّق عليها الترحيل.
drop function if exists public.accept_terms(integer);
drop function if exists public.my_terms_status();
do $$
begin
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'profiles' and column_name = 'terms_accepted_version') then
    update public.profiles set terms_accepted_at = null where terms_accepted_version is not null;
    alter table public.profiles drop column terms_accepted_version;
  end if;
end $$;
