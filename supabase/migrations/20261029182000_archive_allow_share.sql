-- المشاركة لكل عنصر في المكتبة (طلب المالك ٢٠٢٦-١٠-٢٩: «مفتاح التحكم خاص بالإدارة على العنصر من خلال المكتبة»):
-- زرّ الحفظ والمشاركة يظهر للجميع على العنصر المسموح فقط، والسماح يغيّره المالك والمدير وحدهما.
alter table public.family_archive add column if not exists allow_share boolean not null default false;

create or replace function public.trg_family_archive_allow_share_guard()
returns trigger language plpgsql as $$
begin
  if current_user = 'authenticated'
     and ((tg_op = 'INSERT' and new.allow_share)
          or (tg_op = 'UPDATE' and new.allow_share is distinct from old.allow_share))
     and coalesce(public.current_user_role(), '') not in ('owner', 'admin') then
    raise exception 'السماح بالحفظ والمشاركة للمالك والمدير فقط'
      using errcode = '42501', hint = 'not_allowed';
  end if;
  return new;
end $$;

drop trigger if exists trg_family_archive_allow_share_guard on public.family_archive;
create trigger trg_family_archive_allow_share_guard
  before insert or update on public.family_archive
  for each row execute function public.trg_family_archive_allow_share_guard();

-- المفتاح العام صار لكل عنصر — لا حاجة له
delete from public.app_config where key = 'library_share';
