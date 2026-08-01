-- مُستخرَجة من سجل الإنتاج (supabase_migrations.schema_migrations)
-- كانت مطبَّقة على القاعدة لكن ملفها مفقود من المستودع.

-- ١) تعبئة فورية: مزامنة صور مرايا الذكور القديمة من profiles
update public.women_members w
set avatar_url = p.avatar_url
from public.profiles p
where w.id = p.id
  and coalesce(w.avatar_url,'') is distinct from coalesce(p.avatar_url,'');

-- ٢) دالة: تُحدّث صورة عقدة النساء (mirror) عند تغيّر صورة الملف الشخصي
create or replace function public.sync_profile_avatar_to_women()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  update public.women_members set avatar_url = new.avatar_url where id = new.id;
  return new;
end;
$function$;

-- ٣) trigger: يُبقي صورة الذكر في شجرة النساء مطابقة للشجرة العامة
drop trigger if exists trg_sync_profile_avatar_to_women on public.profiles;
create trigger trg_sync_profile_avatar_to_women
after update of avatar_url on public.profiles
for each row
when (coalesce(new.avatar_url,'') is distinct from coalesce(old.avatar_url,''))
execute function public.sync_profile_avatar_to_women();;
