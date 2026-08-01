-- مُستخرَجة من سجل الإنتاج (supabase_migrations.schema_migrations)
-- كانت مطبَّقة على القاعدة لكن ملفها مفقود من المستودع.

-- قائمة العوائل التي تضعها الإدارة، ويختار العضو عائلته منها.
create table if not exists public.family_names (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,
  sort_order  int  not null default 0,
  is_active   boolean not null default true,
  created_at  timestamptz not null default timezone('utc', now())
);

-- اسم عائلة العضو — نصّ مباشر ليبقى ثابتاً لو حُذف من القائمة لاحقاً
alter table public.profiles
  add column if not exists family_name text;

create index if not exists profiles_family_name_idx on public.profiles (family_name);

alter table public.family_names enable row level security;

-- القراءة لكل مسجّل دخول (يحتاجها العضو ليختار عائلته)
drop policy if exists family_names_read on public.family_names;
create policy family_names_read on public.family_names
for select using (auth.uid() is not null);

-- الكتابة للمالك والمدير فقط
drop policy if exists family_names_write on public.family_names;
create policy family_names_write on public.family_names
for all using (current_user_role() = any (array['owner','admin']))
with check (current_user_role() = any (array['owner','admin']));

-- بذرة أولى: عائلة التطبيق نفسها
insert into public.family_names (name, sort_order)
values ('المحمدعلي', 0)
on conflict (name) do nothing;;
