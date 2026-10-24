-- تراجع 20261019120000: يرجّع التاريخين كما كانا
update public.profiles
   set death_date = '1418-01-31', birth_date = '1344-01-01'
 where id = 'e7cef970-8db8-4a13-835c-1b3058fcb69d'
   and death_date is null and birth_date is null;
