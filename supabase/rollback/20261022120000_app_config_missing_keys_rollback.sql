-- تراجع 20261022120000_app_config_missing_keys — يحذف المفاتيح الست فقط إن لم يغيّرها المالك بعد.
delete from public.app_config where key in ('profile_edit_limit_enabled','profile_free_edits','terms_version','age_bands','branch_root_id','branch_extra_heads')
  and updated_by is null;
