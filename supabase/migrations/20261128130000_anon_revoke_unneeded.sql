-- مطبَّق على الحي ٢٠٢٦-١١-٢٨ بعد تجربة begin…rollback
-- صيانة السيرفر ٢٠٢٦-١١-٢٨ (فحص Supabase: ١٤ دالة يقدر يشغّلها الزائر بلا دخول). نسحبها من الزائر فقط حيث لا حاجة لها
-- ولا تستعملها أي سياسة يقرؤها الزائر:
--   register_web_session — ترفض بلا دخول أصلاً («Not authenticated»)؛ الموقع يستدعيها بعد الدخول (authenticated).
--   trg_block_web_registration — دالة مشغّل، لا تُستدعى مباشرة.
-- البقية باقية عمداً: app_config_public / public_family_stats / sms_resend_seconds / occasion_link_is_active (للدخول والموقع
-- والروابط العامة)، و current_user_role / is_moderator / resolve_profile_id / my_women_node / can_handle_admin_request /
-- is_descendant_of_caller / is_team / review_account_ids تُرجع لا شيء للزائر وتستعملها سياسات دورها public (سحبها يحوّل
-- «لا نتائج» إلى خطأ).
-- التراجع: grant execute on function public.register_web_session(text) to anon; grant execute on function public.trg_block_web_registration() to anon;
revoke execute on function public.register_web_session(text) from anon, public;
grant execute on function public.register_web_session(text) to authenticated, service_role;
revoke execute on function public.trg_block_web_registration() from anon, public;
