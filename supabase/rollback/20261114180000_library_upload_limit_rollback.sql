-- تراجع 20261114180000_library_upload_limit: يرجع حدّ المكتبة ٢٥ ميغابايت ويحذف المفتاح والمشغّل
drop trigger if exists trg_app_config_library_upload on public.app_config;
drop function if exists private.sync_library_bucket_limit();
delete from public.app_config where key = 'library_max_upload_mb';
update storage.buckets set file_size_limit = 26214400 where id = 'family-archive';
