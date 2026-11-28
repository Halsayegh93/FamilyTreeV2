-- التراجع عن 20261112180000: يرجع التنفيذ للجميع (PUBLIC) على الدوال الستين كما كانت
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as fn
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = any (array[
         'add_family_child','admin_sender_as_administration','drop_legacy_client_change_notifications',
         'fanout_broadcast_notification','fn_cascade_full_name_to_children','freeze_member_on_ban',
         'get_active_members_now','get_members_activity','get_members_last_signin','get_recent_member_actions',
         'get_recently_active_members','handle_new_user_by_phone','inherit_family_name','is_hr_or_owner',
         'log_women_change_to_activity','mirror_profile_to_women','move_child_gender','notif_fmt','notif_is_admin',
         'notif_short_name','notification_stamp_sender','notifications_fill_subject','notify_admins_on_archive_pending',
         'notify_admins_on_new_pending_member','notify_admins_on_saved_join_request','notify_member_change',
         'prevent_role_self_promotion','register_web_push_subscription','reject_banned_phone_registration',
         'remove_self_wife','remove_self_woman_child','reorder_self_women_children','set_family_name_cascade',
         'set_self_mother','sync_profile_avatar_to_women','sync_profile_delete_to_women','sync_profile_update_to_women',
         'touch_last_active','trg_content_force_pending','trg_device_tokens_exempt_trim','trg_family_links_guard',
         'trg_family_links_protect_delete','trg_mute_review_account_notifications','trg_news_comments_filter',
         'trg_pinned_at_admin_only','trg_profiles_age_rules','trg_profiles_free_conflicting_phone',
         'trg_profiles_link_auth_on_phone_set','trg_profiles_protect_sensitive_columns',
         'trg_profiles_wife_hidden_and_mirrored','trg_profiles_wife_mirror_after','trg_review_account_activity',
         'trg_text_filter','trigger_push_on_notification','unregister_web_push_subscription',
         'update_member_last_seen','update_my_current_screen','update_self_woman_child','women_auto_merge_wife',
         'women_hidden_stamp'])
  loop
    execute format('grant execute on function %s to public', r.fn);
  end loop;
end $$;
