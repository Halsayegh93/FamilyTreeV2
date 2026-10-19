-- تصحيح بيانات (المالك ٢٠٢٦-١٠-١٩ «شيل التاريخ الهجري حاليا»):
-- «محمد(ابواحمد) حسن حسين علي عبدالله المحمدعلي» (e7cef970…) انحفظ له ميلاد 1344-01-01 ووفاة 1418-01-31 —
-- سنوات هجرية مكتوبة كأنها ميلادية. يُمسح التاريخان (يبقى متوفى) لين يتوفّر التاريخ الميلادي.
-- التراجع: supabase/rollback/20261019120000_clear_hijri_dates_abu_ahmad_rollback.sql
update public.profiles
   set death_date = null, birth_date = null
 where id = 'e7cef970-8db8-4a13-835c-1b3058fcb69d'
   and death_date = '1418-01-31'
   and birth_date = '1344-01-01';
