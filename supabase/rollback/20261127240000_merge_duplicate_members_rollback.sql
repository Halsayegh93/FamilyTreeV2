-- تراجع 20261127240000_merge_duplicate_members — يحذف الدالة فقط. ما دُمج قبله يبقى مدموجاً
-- (سجلّ كل رابط نُقل في family_link_history للاسترجاع اليدوي).
drop function if exists public.merge_duplicate_members(uuid, uuid, boolean);
