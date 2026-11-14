-- حدّ حجم الملف في «المكتبة» من السيرفر (طلب المالك ٢٠٢٦-١١-١٤: «١٠٠ ميغا» — «بشكل ما يخترب»)
--
-- مفتاح واحد `app_config.library_max_upload_mb` (يقرؤه الآيفون والأندرويد والموقع عبر `app_config()`؛
-- غيابه = ٢٥ كالنسخ القديمة)، ومشغّل يُبقي حدّ المستودع `family-archive` (storage.buckets.file_size_limit)
-- مطابقاً له دائماً — فيتغيّر المكانان معاً من «إعدادات التطبيق» بلا بناء.
-- النسخ القديمة تمنع محلياً فوق ٢٥ فلا تتأثر. السقف ١٠٠ = حدّ الرفع العام للمشروع (Storage → Settings)
-- يجب أن يكون ≥ هذه القيمة. التراجع: supabase/rollback/20261114180000_library_upload_limit_rollback.sql

create or replace function private.sync_library_bucket_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_mb integer := greatest(1, least(100, coalesce((new.value #>> '{}')::integer, 25)));
begin
  update storage.buckets
     set file_size_limit = v_mb::bigint * 1024 * 1024
   where id = 'family-archive';
  return new;
end;
$$;

revoke all on function private.sync_library_bucket_limit() from public, anon, authenticated;

drop trigger if exists trg_app_config_library_upload on public.app_config;
create trigger trg_app_config_library_upload
  after insert or update of value on public.app_config
  for each row
  when (new.key = 'library_max_upload_mb')
  execute function private.sync_library_bucket_limit();

insert into public.app_config
  (key, value, default_value, kind, min_value, max_value, category, label_ar, help_ar, rules, is_public, sort)
values
  ('library_max_upload_mb', '100'::jsonb, '100'::jsonb, 'int', 5, 100, 'general',
   'المكتبة: أكبر حجم للملف (ميغابايت)',
   'يطبَّق على رفع الملفات والصور في المكتبة من الآيفون والأندرويد والموقع، ويتغيّر معه حدّ التخزين على السيرفر.',
   '{}'::jsonb, false, 220)
on conflict (key) do update set value = excluded.value;
