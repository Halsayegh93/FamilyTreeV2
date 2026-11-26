-- تراجع «أزواج البنات» (20261126170000_outside_family_men).
-- يرجع فقط من علّمه هذا الترحيل (`private.outside_men_backfill`)؛ الأزواج المضافون عبر `add_outside_husband` لا يُمسّون.

drop trigger if exists trg_women_outside_male_flag on public.women_members;
drop function if exists private.women_outside_male_flag();
drop function if exists private.women_outside_male(uuid, uuid, uuid, text);

update public.women_members w
set is_outside_family = false
from private.outside_men_backfill b
where b.id = w.id
  and w.is_outside_family;

drop table if exists private.outside_men_backfill;
