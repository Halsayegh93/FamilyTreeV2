-- تراجع 20261128120000_mother_visibility_by_child — يحذف الدالة. القيم التي اختارها الأبناء على أمّهاتهم تبقى
-- (women_members.spouse_shown / children_shown).
drop function if exists public.set_mother_visibility(boolean, boolean);
