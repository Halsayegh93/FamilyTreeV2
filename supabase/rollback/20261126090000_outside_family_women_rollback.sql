-- تراجع «النساء من خارج العائلة» (20261126090000_outside_family_women).
-- قبل الترحيل ما كانت أي أنثى معلَّمة `is_outside_family` — فالتراجع يرجع كل الإناث false.
-- الأزواج من خارج العائلة (ذكور) لا يُمسّون.

drop trigger if exists trg_women_outside_flag on public.women_members;
drop function if exists private.women_outside_female_flag();
drop function if exists private.women_outside_female(uuid, uuid, uuid, text);

update public.women_members
set is_outside_family = false
where lower(coalesce(gender, '')) = 'female'
  and is_outside_family;

drop table if exists private.outside_women_backfill;
