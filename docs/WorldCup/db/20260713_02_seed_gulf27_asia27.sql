-- ============================================================================
-- Phase 2 data — decorative badge column + two group-stage tournaments.
-- Schema is additive; the match fixtures below were seeded via the Supabase
-- MCP and are reproducible by re-running this file. Dates are provisional
-- (official detailed fixtures not fully released) and adjustable from the admin
-- panel (they DON'T affect team pairings, which are the confirmed draw).
-- ============================================================================

-- decorative hero badge, shown per tournament (edition/year)
alter table public.wc_tournaments add column if not exists badge text;
update public.wc_tournaments set badge = '26' where id = 'wc26' and badge is null;

-- Tournament registry ---------------------------------------------------------
insert into public.wc_tournaments (id, name, short_name, active, format, sort, badge) values
  ('gulf27', 'كأس الخليج ٢٧', 'خليجي ٢٧', true, 'groups', 2, '27'),
  ('asia27', 'كأس آسيا ٢٠٢٧', 'كأس آسيا', true, 'groups', 3, '27')
on conflict (id) do update set
  name = excluded.name, short_name = excluded.short_name, format = excluded.format,
  active = excluded.active, sort = excluded.sort, badge = excluded.badge;

-- Match fixtures were inserted into public.wc_matches with these id ranges:
--   gulf27 : 101–115  (Group A/B = 101–112, SF = 113–114, FINAL = 115)
--   asia27 : 201–251  (Groups A–F = 201–236, R16 = 237–244, QF = 245–248,
--                      SF = 249–250, FINAL = 251)
--
-- Confirmed group draws seeded:
--   Gulf 27  A: السعودية، العراق، عُمان، الكويت
--            B: الإمارات، قطر، البحرين، اليمن
--   Asia 27  A: السعودية، الكويت، عُمان، فلسطين
--            B: أوزبكستان، البحرين، كوريا الشمالية، الأردن
--            C: إيران، سوريا، قيرغيزستان، الصين
--            D: أستراليا، طاجيكستان، العراق، سنغافورة
--            E: كوريا الجنوبية، الإمارات، فيتنام، اليمن
--            F: اليابان، قطر، تايلاند، إندونيسيا
--
-- Knockout matches are seeded with TBD (null) teams; the admin fills them from
-- the "✏️ تعديل الفرق والموعد" control once each group stage concludes.
