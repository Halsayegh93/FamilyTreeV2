-- تراجع 20261127130000_family_tree_men_only: يحذف الحارس ودالته. لا بيانات تتغيّر.
drop trigger if exists trg_zzzz_family_tree_men_only on public.profiles;
drop function if exists private.family_tree_men_only();
