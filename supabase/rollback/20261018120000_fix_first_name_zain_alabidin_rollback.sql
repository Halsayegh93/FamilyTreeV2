-- تراجع 20261018120000: يرجّع الاسم الأول «زين» كما كان
update public.profiles
   set first_name = 'زين'
 where id = 'c74b5feb-26db-4a5f-a294-956e4dbeee48'
   and first_name = 'زين العابدين';
