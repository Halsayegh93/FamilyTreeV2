-- فرض «إخفاء الهاتف» على السيرفر بدل الواجهة وحدها.
-- القياس: ٤٩ رقماً مسجَّلاً، ٤٨ منها ظاهرة بإرادة أصحابها (التطبيق دليل عائلي)،
-- وواحد مخفيّ بطلب صاحبه — ومع ذلك كان يُشحن لكل جهاز ضمن جلب الأعضاء الكامل
-- ويُخفى في الواجهة فقط. هذه الدالة هي المسار الوحيد المسموح لقراءة رقم،
-- فيصير الإخفاء حقيقياً ويتوقّف بثّ الأرقام كلّها مع كل مزامنة.
create or replace function public.get_member_phone(p_id uuid)
returns text
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare me uuid := coalesce(
      nullif(auth.jwt() -> 'app_metadata' ->> 'profile_id', '')::uuid,
      nullif(auth.jwt() -> 'user_metadata' ->> 'profile_id', '')::uuid,
      auth.uid());
    r record;
begin
  if me is null then raise exception 'not_authenticated'; end if;
  select phone_number, coalesce(is_phone_hidden,false) as hidden
    into r from public.profiles where id = p_id;
  if not found or r.phone_number is null then return null; end if;
  -- صاحب الرقم يراه دائماً · الإدارة تراه للتواصل · وغيرهما إن لم يُخفَ
  if p_id = me
     or public.current_user_role() = any (array['owner','admin','monitor','supervisor'])
     or not r.hidden
  then return r.phone_number; end if;
  return null;
end; $$;

revoke all on function public.get_member_phone(uuid) from public, anon;
grant execute on function public.get_member_phone(uuid) to authenticated;
