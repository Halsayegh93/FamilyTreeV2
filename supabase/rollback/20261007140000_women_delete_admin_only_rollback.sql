-- تراجع 20261007140000: سياسة الكتابة الواحدة على شجرة النساء كما كانت على السيرفر الحي
-- (ALL للمالك والمدير والمراقب — المراقب يحذف مجدداً، للطوارئ فقط)

drop policy if exists women_members_insert on public.women_members;
drop policy if exists women_members_update on public.women_members;
drop policy if exists women_members_delete on public.women_members;
drop policy if exists women_members_write on public.women_members;

create policy women_members_write on public.women_members
  for all to authenticated
  using ((public.current_user_role() = ANY (ARRAY['owner'::text, 'admin'::text, 'monitor'::text])))
  with check ((public.current_user_role() = ANY (ARRAY['owner'::text, 'admin'::text, 'monitor'::text])));
